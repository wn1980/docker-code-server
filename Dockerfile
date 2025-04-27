FROM --platform=linux/x86-64 ubuntu:noble

# Define ARG for host docker group GID (Set explicitly to 988 as requested)
# This GID is primarily for Docker-OUTSIDE-Docker (mounting host socket)
# For Docker-IN-Docker, the internal daemon manages its own socket permissions.
ARG HOST_DOCKER_GID=988

# Update package lists first
RUN apt-get update

# Install base dependencies, including supervisor, clangd, wget (Node.js prereqs kept just in case)
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

 # Add Docker's official GPG key & repository (Unchanged)
RUN install -m 0755 -d /etc/apt/keyrings && \
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
chmod a+r /etc/apt/keyrings/docker.asc && \
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null && \
apt-get update

# Install Docker Engine (docker-ce), CLI, containerd.io, and Docker Compose plugin for DinD support
# Note: Running Docker-in-Docker requires starting the container with the --privileged flag.
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

# Install Miniconda
RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh && \
    bash ~/miniconda.sh -b -p $MINICONDA_PATH && \
    rm ~/miniconda.sh && \
    # Set auto_activate_base to false system-wide
    $MINICONDA_PATH/bin/conda config --system --set auto_activate_base false && \
    # Clean up conda cache
    $MINICONDA_PATH/bin/conda clean -afy

# Create Conda environment 'dev_env' with specified tools
RUN conda create -n dev_env -c conda-forge \
    python=3.12 \
    nodejs=22 \
    cmake \
    cxx-compiler \
    make \
    gdb \
    -y && \
    conda clean -afy

# Configure existing ubuntu user
RUN useradd -m -s /bin/bash ubuntu || true && \
    usermod -u 1000 ubuntu && \
    groupmod -g 1000 ubuntu && \
    mkdir -p /home/ubuntu/.config/code-server && \
    chown -R ubuntu:ubuntu /home/ubuntu

# Create docker group with specific GID from build argument, then add ubuntu user
# This ensures the user inside the container can access the mounted docker socket (DooD)
# AND potentially the internal docker socket (DinD) if the GIDs align or permissions are open.
# The internal dockerd will manage /var/run/docker.sock inside the container.
RUN groupadd --gid ${HOST_DOCKER_GID} docker || groupmod -g ${HOST_DOCKER_GID} docker || true
RUN usermod -aG docker ubuntu

# Initialize Conda for the ubuntu user's bash shell and set default env
USER ubuntu
RUN conda init bash && \
    echo "conda activate dev_env" >> /home/ubuntu/.bashrc

# Switch back to root for subsequent steps
USER root

# Allow ubuntu user to use sudo without password (Already included)
RUN echo 'ubuntu ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/ubuntu-nopasswd && \
    chmod 0440 /etc/sudoers.d/ubuntu-nopasswd

# Define code-server version (Already present in user's file)
ARG CODER_VERSION=4.99.3

# Install specific code-server version (globally)
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --version ${CODER_VERSION}

# Generate SSL certificates (Note: Still not used by the command)
RUN mkdir -p /opt/code-server/certs && \
    openssl req -x509 -nodes -days 365 \
      -newkey rsa:2048 \
      -keyout /opt/code-server/certs/key.pem \
      -out /opt/code-server/certs/cert.pem \
      -subj "/C=US/ST=California/L=San Francisco/O=IT/CN=localhost" && \
    chown -R ubuntu:ubuntu /opt/code-server/certs

# Switch to ubuntu user for extension installation
USER ubuntu

# Install VS Code extensions (Uncommented in user's file)
RUN code-server --install-extension googlecloudtools.cloudcode --force # Gemini / Google Cloud
RUN code-server --install-extension llvm-vs-code-extensions.vscode-clangd --force # clangd
RUN code-server --install-extension ms-python.python --force         # Python
RUN code-server --install-extension ms-vscode.cmake-tools --force    # CMake Tools
RUN code-server --install-extension DanielSanMedium.dscodegpt --force # CodeGPT

# Set Workdir as ubuntu user
WORKDIR /home/ubuntu/project

# Switch back to root user before CMD to start supervisord as root
USER root

# Copy local supervisor directory structure
# IMPORTANT: Ensure your supervisor/supervisord.conf includes a program
#            to start the Docker daemon (dockerd). See example below.
COPY supervisor /opt/supervisor
RUN chown -R ubuntu:ubuntu /opt/supervisor

VOLUME ["/home/ubuntu/.config", "/home/ubuntu/project"]
EXPOSE 8443

# Healthcheck removed or needs update for supervisor/http
# ENTRYPOINT removed

# Run supervisord using the main configuration file
# Supervisord should be configured to start dockerd and code-server.
CMD ["/usr/bin/supervisord", "-c", "/opt/supervisor/supervisord.conf"]

# --- IMPORTANT NOTES FOR DOCKER-IN-DOCKER ---
#
# 1. Runtime Flag: You MUST run this container with the --privileged flag:
#    docker run --privileged -p 8443:8443 ... your-image-name
#
# 2. Supervisor Configuration: You need to add a program block for the
#    Docker daemon in your local `supervisor/supervisord.conf` file before building.
#    Example `[program:dockerd]` block:
#
#    [program:dockerd]
#    command=/usr/bin/dockerd --host=unix:///var/run/docker.sock --storage-driver=vfs
#    autostart=true
#    autorestart=true
#    priority=10 ; Start dockerd before other services like code-server if needed
#    stdout_logfile=/var/log/supervisor/dockerd-stdout.log
#    stderr_logfile=/var/log/supervisor/dockerd-stderr.log
#
#    (Ensure /var/log/supervisor directory exists or adjust log paths)
#    Using 'vfs' storage driver is often recommended for DinD to avoid issues with overlayfs on top of overlayfs.
#
# 3. User Permissions: The `ubuntu` user is added to the `docker` group created
#    with HOST_DOCKER_GID. The internal `dockerd` should create /var/run/docker.sock
#    owned by root:docker (using the internal docker group GID). If the GIDs match
#    or the socket permissions are group-writable, the `ubuntu` user should have access.
#    If not, you might need to adjust group memberships or permissions after dockerd starts.
