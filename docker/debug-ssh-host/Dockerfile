FROM debian:12-slim

ARG IMAGE_VERSION=latest

LABEL org.opencontainers.image.title="be96-debug" \
      org.opencontainers.image.description="SSH debug toolbox for Docker-only BE96/iStoreNAS hosts" \
      org.opencontainers.image.version="${IMAGE_VERSION}"

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    coreutils \
    curl \
    docker.io \
    file \
    iproute2 \
    iptables \
    iputils-ping \
    kmod \
    less \
    lsof \
    net-tools \
    openssh-server \
    procps \
    psmisc \
    strace \
    sudo \
    tcpdump \
    util-linux \
    vim-tiny \
    wget \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /run/sshd /home/debug/.ssh \
  && useradd -m -s /bin/bash debug \
  && echo 'debug ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/debug \
  && chmod 0440 /etc/sudoers.d/debug \
  && chown -R debug:debug /home/debug/.ssh \
  && chmod 0700 /home/debug/.ssh \
  && sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config \
  && sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config \
  && sed -i 's/^#\?PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config \
  && printf '%s\n' \
    'UsePAM no' \
    'AllowUsers debug' \
    >> /etc/ssh/sshd_config

COPY entrypoint.sh /usr/local/bin/debug-ssh-entrypoint
COPY istoreos-manager.sh /usr/local/bin/istoreos-manager

RUN chmod 0755 /usr/local/bin/debug-ssh-entrypoint /usr/local/bin/istoreos-manager

ENV DEBUG_SSH_PORT=2223 \
    ISTOREOS_AUTO_START=0 \
    ISTOREOS_CONTAINER=istoreos \
    ISTOREOS_IMAGE=linkease/istore24.10-in-be96:latest \
    ISTOREOS_BRIDGE=br-istoreos \
    ISTOREOS_PARENT=eth0

EXPOSE 2223

ENTRYPOINT ["/usr/local/bin/debug-ssh-entrypoint"]
