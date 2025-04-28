# Use the base image without forcing the platform. Docker will select
# the appropriate architecture based on the build context or --platform flag.
FROM ubuntu:noble

# Define ARG for host docker group GID (Set explicitly to 988 as requested)
ARG HOST_DOCKER_GID=988

# Define automatic build arguments provided by BuildKit
# TARGETARCH will be 'amd64' or 'arm64' depending on the build target
ARG TARGETARCH

# Update package lists first
RUN apt-get update

# Install base dependencies, including supervisor, clangd, wget
# These packages are generally available for both amd64 and arm64
RUN apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    sudo \
    git \
    openssl \
    net-tools \
    supervisor \
    clangd \
    wget \
 && rm -rf /var/lib/apt/lists/* \
 && apt-get clean

 # Add Docker's official GPG key & repository
 # Uses dpkg --print-architecture, which correctly identifies the target arch
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update

# Install Docker Engine, CLI, containerd.io, and Docker Compose plugin
# apt will fetch the correct architecture versions
RUN apt-get update && apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-compose-plugin \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

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

# Create docker group with specific GID from build argument, then add ubuntu user
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

# Switch to ubuntu user for extension installation
USER ubuntu

# Install VS Code extensions
# These extensions generally support multiple architectures or are architecture-agnostic
RUN code-server --install-extension googlecloudtools.cloudcode --force # Gemini / Google Cloud
RUN code-server --install-extension llvm-vs-code-extensions.vscode-clangd --force # clangd
RUN code-server --install-extension ms-python.python --force         # Python
RUN code-server --install-extension ms-vscode.cmake-tools --force    # CMake Tools
RUN code-server --install-extension DanielSanMedium.dscodegpt --force # CodeGPT

# Set Workdir as ubuntu user
WORKDIR /home/ubuntu/projects

# Switch back to root user before CMD to start supervisord as root
USER root

# Copy local supervisor directory structure
COPY supervisor /opt/supervisor
RUN chown -R ubuntu:ubuntu /opt/supervisor

VOLUME ["/home/ubuntu/.config", "/home/ubuntu/projects"]
EXPOSE 8443

# Run supervisord using the main configuration file
# Ensure supervisor config starts dockerd (see previous notes) and code-server
CMD ["/usr/bin/supervisord", "-c", "/opt/supervisor/supervisord.conf"]

# --- IMPORTANT NOTES FOR DOCKER-IN-DOCKER (Apply to both architectures) ---
#
# 1. Runtime Flag: You MUST run this container with the --privileged flag.
# 2. Supervisor Configuration: Ensure your supervisor/supervisord.conf starts dockerd.
#    Example [program:dockerd] block:
#    [program:dockerd]
#    command=/usr/bin/dockerd --host=unix:///var/run/docker.sock --storage-driver=vfs
#    autostart=true
#    autorestart=true
#    priority=10
#    stdout_logfile=/var/log/supervisor/dockerd-stdout.log
#    stderr_logfile=/var/log/supervisor/dockerd-stderr.log
# 3. User Permissions: The ubuntu user is added to the docker group.
