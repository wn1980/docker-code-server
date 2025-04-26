FROM ubuntu:noble

# Install dependencies
RUN apt-get update && \
    apt-get install -y \
    curl \
    sudo \
    git \
    openssl \
    net-tools \
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

# Install code-server
ARG CODER_VERSION=4.23.0
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --version ${CODER_VERSION}

# Generate SSL certificates (Note: These are no longer used by the CMD below)
RUN mkdir -p /etc/code-server/certs && \
    openssl req -x509 -nodes -days 365 \
      -newkey rsa:2048 \
      -keyout /etc/code-server/certs/key.pem \
      -out /etc/code-server/certs/cert.pem \
      -subj "/C=US/ST=California/L=San Francisco/O=IT/CN=localhost" && \
    chown -R ubuntu:ubuntu /etc/code-server/certs

# Final config and extension installation
USER ubuntu

# Install Google Cloud Code extension (includes Gemini features)
RUN code-server --install-extension googlecloudtools.cloudcode --force

WORKDIR /home/ubuntu/project

VOLUME ["/home/ubuntu/.config/code-server", "/home/ubuntu/project"]
EXPOSE 8443

# Healthcheck is removed as it targeted HTTPS, which is now disabled.
# A new healthcheck could be added targeting HTTP if needed.
# HEALTHCHECK --interval=30s --timeout=10s \
#   CMD curl --fail https://localhost:8443/ || exit 1

ENTRYPOINT ["code-server"]
# Modified CMD to run without HTTPS
CMD ["--bind-addr", "0.0.0.0:8443", "--auth", "none"]