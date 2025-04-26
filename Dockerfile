FROM ubuntu:noble

# Install dependencies, including supervisor
RUN apt-get update && \
    apt-get install -y \
    curl \
    sudo \
    git \
    openssl \
    net-tools \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

# Configure existing ubuntu user
RUN useradd -m -s /bin/bash ubuntu || true && \
    usermod -u 1000 ubuntu && \
    groupmod -g 1000 ubuntu && \
    mkdir -p /home/ubuntu/.config/code-server && \
    chown -R ubuntu:ubuntu /home/ubuntu

# Allow ubuntu user to use sudo without password
RUN echo 'ubuntu ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/ubuntu-nopasswd && \
    chmod 0440 /etc/sudoers.d/ubuntu-nopasswd

# Create user-specific supervisor config directory
RUN mkdir -p /home/ubuntu/.conf.d && \
    chown -R ubuntu:ubuntu /home/ubuntu/.conf.d

# Define code-server version
ARG CODER_VERSION=4.99.3

# Install specific code-server version
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --version ${CODER_VERSION}

# Generate SSL certificates (Note: Still not used by the command)
RUN mkdir -p /etc/code-server/certs && \
    openssl req -x509 -nodes -days 365 \
      -newkey rsa:2048 \
      -keyout /etc/code-server/certs/key.pem \
      -out /etc/code-server/certs/cert.pem \
      -subj "/C=US/ST=California/L=San Francisco/O=IT/CN=localhost" && \
    chown -R ubuntu:ubuntu /etc/code-server/certs

# Create main Supervisor configuration file (points include to user home)
RUN mkdir -p /etc/supervisor/conf.d/ && \
    echo '[supervisord]' > /etc/supervisor/supervisord.conf && \
    echo 'nodaemon=true' >> /etc/supervisor/supervisord.conf && \
    echo '' >> /etc/supervisor/supervisord.conf && \
    echo '[include]' >> /etc/supervisor/supervisord.conf && \
    echo 'files = /home/ubuntu/.conf.d/*.conf' >> /etc/supervisor/supervisord.conf

# Create Supervisor configuration for code-server in user home directory
RUN echo '[program:code-server]' > /home/ubuntu/.conf.d/code-server.conf && \
    echo 'command=/usr/bin/code-server --bind-addr 0.0.0.0:8443 --auth none' >> /home/ubuntu/.conf.d/code-server.conf && \
    echo 'user=ubuntu' >> /home/ubuntu/.conf.d/code-server.conf && \
    echo 'directory=/home/ubuntu/project' >> /home/ubuntu/.conf.d/code-server.conf && \
    echo 'autostart=true' >> /home/ubuntu/.conf.d/code-server.conf && \
    echo 'autorestart=true' >> /home/ubuntu/.conf.d/code-server.conf && \
    echo 'stdout_logfile=/dev/stdout' >> /home/ubuntu/.conf.d/code-server.conf && \
    echo 'stdout_logfile_maxbytes=0' >> /home/ubuntu/.conf.d/code-server.conf && \
    echo 'stderr_logfile=/dev/stderr' >> /home/ubuntu/.conf.d/code-server.conf && \
    echo 'stderr_logfile_maxbytes=0' >> /home/ubuntu/.conf.d/code-server.conf && \
    chown ubuntu:ubuntu /home/ubuntu/.conf.d/code-server.conf

# Final config and extension installation (run as ubuntu)
USER ubuntu

# Install Google Cloud Code extension (includes Gemini features)
RUN code-server --install-extension googlecloudtools.cloudcode --force

WORKDIR /home/ubuntu/project

VOLUME ["/home/ubuntu/.config/code-server", "/home/ubuntu/project"]
EXPOSE 8443

# Healthcheck removed or needs update for supervisor/http
# ENTRYPOINT removed

# Run supervisord using the main configuration file
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]