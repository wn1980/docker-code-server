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

# Install code-server
ARG CODER_VERSION=4.23.0
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --version ${CODER_VERSION}

# Generate SSL certificates
RUN mkdir -p /etc/code-server/certs && \
    openssl req -x509 -nodes -days 365 \
      -newkey rsa:2048 \
      -keyout /etc/code-server/certs/key.pem \
      -out /etc/code-server/certs/cert.pem \
      -subj "/C=US/ST=California/L=San Francisco/O=IT/CN=localhost" && \
    chown -R ubuntu:ubuntu /etc/code-server/certs

# Final config
USER ubuntu
WORKDIR /home/ubuntu/project

VOLUME ["/home/ubuntu/.config/code-server", "/home/ubuntu/project"]
EXPOSE 8443

HEALTHCHECK --interval=30s --timeout=10s \
  CMD curl --fail https://localhost:8443/ || exit 1

ENTRYPOINT ["code-server"]
CMD ["--bind-addr", "0.0.0.0:8443", "--cert", "/etc/code-server/certs/cert.pem", "--cert-key", "/etc/code-server/certs/key.pem", "--auth", "none"]