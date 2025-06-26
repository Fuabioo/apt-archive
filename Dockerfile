FROM ubuntu:22.04

RUN apt update && \
    apt install -y wget curl gnupg jq dpkg-dev apt-utils tar rng-tools && \
    wget https://github.com/mikefarah/yq/releases/download/v4.45.4/yq_linux_amd64 -O /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq

RUN apt install -y ca-certificates libnss3-tools nginx && \
    curl -sJLO "https://dl.filippo.io/mkcert/latest?for=linux/amd64" && \
    chmod +x mkcert-v*-linux-amd64 && \
    cp mkcert-v*-linux-amd64 /usr/local/bin/mkcert

RUN mkcert -install && \
    mkdir -p /etc/nginx/certs && \
    cd /etc/nginx/certs && \
    mkcert localhost

# WARNING: This GPG key generation is ONLY for local testing/development
# NEVER use this in production - it creates ephemeral keys that are not secure
RUN mkdir -p ~/.gnupg && \
    chmod 700 ~/.gnupg && \
    echo "pinentry-mode loopback" >> ~/.gnupg/gpg.conf && \
    echo "use-agent" >> ~/.gnupg/gpg.conf && \
    echo "%echo Generating ephemeral GPG key for local testing..." > /tmp/gpg-batch.conf && \
    echo "Key-Type: RSA" >> /tmp/gpg-batch.conf && \
    echo "Key-Length: 2048" >> /tmp/gpg-batch.conf && \
    echo "Subkey-Type: RSA" >> /tmp/gpg-batch.conf && \
    echo "Subkey-Length: 2048" >> /tmp/gpg-batch.conf && \
    echo "Name-Real: APT Archive Test Key" >> /tmp/gpg-batch.conf && \
    echo "Name-Comment: EPHEMERAL - FOR TESTING ONLY" >> /tmp/gpg-batch.conf && \
    echo "Name-Email: test@localhost.local" >> /tmp/gpg-batch.conf && \
    echo "Expire-Date: 30d" >> /tmp/gpg-batch.conf && \
    echo "%no-protection" >> /tmp/gpg-batch.conf && \
    echo "%commit" >> /tmp/gpg-batch.conf && \
    echo "%echo GPG key generation complete" >> /tmp/gpg-batch.conf

# Generate the GPG key with better entropy
RUN service rng-tools start || true && \
    gpg --batch --generate-key /tmp/gpg-batch.conf && \
    rm /tmp/gpg-batch.conf

# GPG environment variables will be set at runtime by the set-gpg-env.sh script
# Note: These are ephemeral keys for testing only - never use in production

# Script to set GPG environment variables at runtime
RUN cat <<'EOF' > /usr/local/bin/set-gpg-env.sh
#!/bin/bash
# Export GPG key ID and private key as environment variables
export GPG_KEY_ID=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep 'sec ' | sed 's/.*rsa[0-9]*\/\([A-F0-9]\{16\}\).*/\1/')
export GPG_PRIVATE_KEY=$(gpg --armor --export-secret-keys $GPG_KEY_ID 2>/dev/null | base64 -w 0)
echo "GPG_KEY_ID=$GPG_KEY_ID" > /tmp/gpg-env
echo "GPG_PRIVATE_KEY=$GPG_PRIVATE_KEY" >> /tmp/gpg-env
source /tmp/gpg-env
EOF

RUN chmod +x /usr/local/bin/set-gpg-env.sh

# Source GPG environment variables in bashrc for interactive shells
RUN echo "source /usr/local/bin/set-gpg-env.sh" >> ~/.bashrc
