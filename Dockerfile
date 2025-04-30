# Use the base image without forcing the platform. Docker will select
# the appropriate architecture based on the build context or --platform flag.
# Pinning to a specific date tag for reproducibility
FROM ubuntu:noble-20250404

# Define ARG for host docker group GID.
# IMPORTANT: Set this at build time (--build-arg HOST_DOCKER_GID=$(getent group docker | cut -d: -f3))
# to match your HOST's docker group GID for socket permissions.
# Defaulting to 988 as per original, but overriding is recommended.
ARG HOST_DOCKER_GID=988

# Define automatic build arguments provided by BuildKit
# TARGETARCH will be 'amd64' or 'arm64' depending on the build target
ARG TARGETARCH

# Install base dependencies, including supervisor, clangd, wget, curl
# These packages are generally available for both amd64 and arm64
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Base requirement
    ca-certificates \ 
    curl \
    gnupg \
    sudo \
    git \
    openssl \
    net-tools \
    supervisor \
    clangd \
    # For Miniconda download
    wget \ 
 && rm -rf /var/lib/apt/lists/*

 # Add Docker's official GPG key & repository for CLI tools
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    # Install Docker CLI tools in the same layer
    apt-get update && apt-get install -y --no-install-recommends \
    docker-ce-cli \
    docker-compose-plugin \
    docker-buildx-plugin \
 && rm -rf /var/lib/apt/lists/*

# Set environment variable for Miniconda installation path
ENV MINICONDA_PATH /opt/miniconda
# Set environment variable for updated PATH (Conda added)
ENV PATH $MINICONDA_PATH/bin:$PATH

# Install Miniconda - Dynamically select the correct installer based on TARGETARCH
RUN \
    # Determine the architecture suffix for the Miniconda filename
    case ${TARGETARCH} in \
        amd64) MINICONDA_ARCH_SUFFIX="x86_64" ;; \
        arm64) MINICONDA_ARCH_SUFFIX="aarch64" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}"; exit 1 ;; \
    esac && \
    # Download the correct installer
    wget "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-${MINICONDA_ARCH_SUFFIX}.sh" -O ~/miniconda.sh && \
    # Install Miniconda
    bash ~/miniconda.sh -b -p $MINICONDA_PATH && \
    rm ~/miniconda.sh && \
    # Configure Conda
    $MINICONDA_PATH/bin/conda config --system --set auto_activate_base false && \
    $MINICONDA_PATH/bin/conda clean -afy

# Create Conda environment 'dev_env' with specified tools
# Conda-forge generally has good multi-arch support (linux-64, linux-aarch64)
RUN conda create -n dev_env -c conda-forge \
    python=3.12 \
    nodejs=22 \
    cmake \
    cxx-compiler \
    make \
    gdb \
    -y && \
    conda clean -afy

# Configure existing ubuntu user (architecture independent)
RUN useradd -m -s /bin/bash ubuntu || true && \
    usermod -u 1000 ubuntu && \
    groupmod -g 1000 ubuntu && \
    mkdir -p /home/ubuntu/.config/code-server && \
    chown -R ubuntu:ubuntu /home/ubuntu

# Create docker group with specific GID from build argument to match HOST docker group GID.
# Then add ubuntu user to this group to allow access to the mounted docker socket.
# (architecture independent)
RUN groupadd --gid ${HOST_DOCKER_GID} docker || groupmod -g ${HOST_DOCKER_GID} docker || true
RUN usermod -aG docker ubuntu

# Initialize Conda for the ubuntu user's bash shell and set default env
USER ubuntu
RUN conda init bash && \
    echo "conda activate dev_env" >> /home/ubuntu/.bashrc

# Switch back to root for subsequent steps
USER root

# Allow ubuntu user to use sudo without password (architecture independent)
RUN echo 'ubuntu ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/ubuntu-nopasswd && \
    chmod 0440 /etc/sudoers.d/ubuntu-nopasswd

# Define code-server version
ARG CODER_VERSION=4.99.3

# Install specific code-server version (globally)
# The official install script should automatically detect the architecture
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --version ${CODER_VERSION}

# Generate SSL certificates (architecture independent)
RUN mkdir -p /opt/code-server/certs && \
    openssl req -x509 -nodes -days 365 \
      -newkey rsa:2048 \
      -keyout /opt/code-server/certs/key.pem \
      -out /opt/code-server/certs/cert.pem \
      -subj "/C=US/ST=California/L=San Francisco/O=IT/CN=localhost" && \
    chown -R ubuntu:ubuntu /opt/code-server/certs

    # Switch to ubuntu user for subsequent steps
USER ubuntu

# Install VS Code extensions
# Run as root, as code-server was installed globally by root
# These extensions generally support multiple architectures or are architecture-agnostic
# Install extensions in a single layer. Removed --force, add back if needed for specific extensions.
RUN code-server --install-extension llvm-vs-code-extensions.vscode-clangd \
 && code-server --install-extension ms-python.python \
 && code-server --install-extension ms-vscode.cmake-tools \
 && code-server --install-extension google.geminicodeassist \
 && code-server --install-extension DanielSanMedium.dscodegpt \
 && code-server --install-extension rjmacarthy.twinny \
 && code-server --install-extension ms-azuretools.vscode-docker 
 
# Set Workdir as ubuntu user
WORKDIR /home/ubuntu/projects

# Switch back to root user before CMD to start supervisord as root
USER root

# Copy local supervisor directory structure
# IMPORTANT: Ensure supervisor/supervisord.conf DOES NOT try to start dockerd
COPY supervisor /opt/supervisor
RUN chown -R ubuntu:ubuntu /opt/supervisor

VOLUME ["/home/ubuntu/.config", "/home/ubuntu/projects"]
EXPOSE 8443

# Run supervisord using the main configuration file
# Supervisor should now only manage code-server (and any other non-docker services)
CMD ["/usr/bin/supervisord", "-c", "/opt/supervisor/supervisord.conf"]

# --- IMPORTANT NOTES FOR SHARING HOST DOCKER DAEMON ---
#
# 1. Runtime Flags: You MUST run this container with:
#    -v /var/run/docker.sock:/var/run/docker.sock
#    This mounts the host's Docker socket into the container.
#
# 2. Build Argument: You SHOULD build this image with:
#    --build-arg HOST_DOCKER_GID=$(getent group docker | cut -d: -f3 || echo 988)
#    Replace '988' with the actual GID if the command fails. This ensures the 'docker'
#    group inside the container has the same GID as the 'docker' group on your host,
#    granting the 'ubuntu' user permission to use the mounted socket. If the GID inside
#    doesn't match the GID owning the socket on the host, you'll get permission errors.
#
# 3. Supervisor Configuration: Ensure your supervisor/supervisord.conf file
#    DOES NOT contain a [program:dockerd] section. Supervisor should only manage
#    code-server and any other desired services within the container.
#
# 4. Privileged Flag: The --privileged flag is NO LONGER required for Docker functionality
#    with this setup (though code-server or other tools might still need specific capabilities).
