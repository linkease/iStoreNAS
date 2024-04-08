FROM debian:buster

COPY sources.list /etc/apt/sources.list

RUN apt-get update &&\
    apt-get install -y \
        sudo time git-core build-essential g++ bash make \
        libssl-dev patch libncurses5 libncurses5-dev zlib1g-dev gawk \
        flex gettext wget unzip bzip2 xz-utils device-tree-compiler rsync curl python3 python3-distutils-extra python3-setuptools \
        libsnmp-dev liblzma-dev libpam0g-dev cpio rsync gcc-multilib && \
    apt-get clean && \
    useradd -m builder && \
    echo 'user ALL=NOPASSWD: ALL' > /etc/sudoers.d/builder

# set system wide dummy git config
RUN git config --system user.name "builder" && git config --system user.email "builder@example.com"

USER builder

VOLUME /work
VOLUME /work/ib

ENV WORK_SOURCE=/work
ENV WORK_TARGET=x86_64

COPY build.sh /bin/build.sh

WORKDIR /work

ENTRYPOINT [ "/bin/build.sh" ]

