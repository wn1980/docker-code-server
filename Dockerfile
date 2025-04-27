FROM --platform=linux/x86-64 ubuntu:noble

# Define ARG for host docker group GID (Set explicitly to 988 as requested)
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
# This ensures the user inside the container can access the mounted docker socket
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
WORKDIR /home/ubuntu/projects

# Switch back to root user before CMD to start supervisord as root
USER root

# Copy local supervisor directory structure
COPY supervisor /opt/supervisor
RUN chown -R ubuntu:ubuntu /opt/supervisor

VOLUME ["/home/ubuntu/.config", "/home/ubuntu/projects"]
EXPOSE 8443

# Healthcheck removed or needs update for supervisor/http
# ENTRYPOINT removed

# Run supervisord using the main configuration file
CMD ["/usr/bin/supervisord", "-c", "/opt/supervisor/supervisord.conf"]