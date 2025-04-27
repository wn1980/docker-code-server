FROM ubuntu:noble

# Define ARG for host docker group GID
ARG HOST_DOCKER_GID=988 # Provide a default, but override during build

# Update package lists first
RUN apt-get update

# Install base dependencies... (rest of this block is unchanged)
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

# Install Docker CLI, containerd.io, and Docker Compose plugin (Unchanged)
RUN apt-get install -y docker-ce-cli containerd.io docker-compose-plugin && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Set environment variable for Miniconda installation path (Unchanged)
ENV MINICONDA_PATH /opt/miniconda
# Set environment variable for updated PATH (Conda added) (Unchanged)
ENV PATH $MINICONDA_PATH/bin:$PATH

# Install Miniconda (Unchanged)
RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh && \
    bash ~/miniconda.sh -b -p $MINICONDA_PATH && \
    rm ~/miniconda.sh && \
    $MINICONDA_PATH/bin/conda config --system --set auto_activate_base false && \
    $MINICONDA_PATH/bin/conda clean -afy

# Create Conda environment 'dev_env' with specified tools (Unchanged)
RUN conda create -n dev_env -c conda-forge \
    python=3.12 \
    nodejs=22 \
    cmake \
    cxx-compiler \
    make \
    gdb \
    -y && \
    conda clean -afy

# Configure existing ubuntu user (Unchanged)
RUN useradd -m -s /bin/bash ubuntu || true && \
    usermod -u 1000 ubuntu && \
    groupmod -g 1000 ubuntu && \
    mkdir -p /home/ubuntu/.config/code-server && \
    chown -R ubuntu:ubuntu /home/ubuntu

# Create docker group with specific GID from build argument, then add ubuntu user
RUN groupadd --gid ${HOST_DOCKER_GID} docker || groupmod -g ${HOST_DOCKER_GID} docker || true
RUN usermod -aG docker ubuntu

# Initialize Conda for the ubuntu user's bash shell and set default env (Unchanged)
USER ubuntu
RUN conda init bash && \
    echo "conda activate dev_env" >> /home/ubuntu/.bashrc

# Switch back to root for subsequent steps (Unchanged)
USER root

# Allow ubuntu user to use sudo without password (Already included) (Unchanged)
RUN echo 'ubuntu ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/ubuntu-nopasswd && \
    chmod 0440 /etc/sudoers.d/ubuntu-nopasswd

# Define code-server version (Unchanged)
ARG CODER_VERSION=4.99.3

# Install specific code-server version (globally) (Unchanged)
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --version ${CODER_VERSION}

# Generate SSL certificates (Note: Still not used by the command) (Unchanged)
RUN mkdir -p /opt/code-server/certs && \
    openssl req -x509 -nodes -days 365 \
      -newkey rsa:2048 \
      -keyout /opt/code-server/certs/key.pem \
      -out /opt/code-server/certs/cert.pem \
      -subj "/C=US/ST=California/L=San Francisco/O=IT/CN=localhost" && \
    chown -R ubuntu:ubuntu /opt/code-server/certs

# Copy supervisor directory and configuration files (Unchanged)
COPY supervisor /opt/supervisor
RUN chown -R ubuntu:ubuntu /opt/supervisor

# Switch to ubuntu user (Commented out Extension Installation) (Unchanged)
USER ubuntu

# Install VS Code extensions (Commented out) (Unchanged)
# RUN code-server --install-extension googlecloudtools.cloudcode --force # Gemini / Google Cloud
# RUN code-server --install-extension llvm-vs-code-extensions.vscode-clangd --force # clangd
# RUN code-server --install-extension ms-python.python --force         # Python
# RUN code-server --install-extension ms-vscode.cmake-tools --force    # CMake Tools

# Set Workdir as ubuntu user (Unchanged)
WORKDIR /home/ubuntu/project

# Switch back to root user before CMD to start supervisord as root (Unchanged)
USER root

VOLUME ["/home/ubuntu/.config", "/home/ubuntu/project"] # (Unchanged)
EXPOSE 8443 

# Healthcheck removed or needs update for supervisor/http (Unchanged)
# ENTRYPOINT removed (Unchanged)

# Run supervisord using the main configuration file (Unchanged)
CMD ["/usr/bin/supervisord", "-c", "/opt/supervisor/supervisord.conf"]