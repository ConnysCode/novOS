# Cross toolchain for the TV's 32-bit ARM userland.
# The TV uses the softfp ABI (ELF flags 0x5000200), which matches Debian armel
# and not armhf. Buster's Qt 5.11 headers work against the TV's Qt 5.12 runtime.
# Only headers are unpacked: the module resolves Qt and GLES inside surface-manager.
FROM debian:buster-slim
RUN printf 'deb http://archive.debian.org/debian buster main\n' > /etc/apt/sources.list \
 && dpkg --add-architecture armel \
 && apt-get -o Acquire::Check-Valid-Until=false -o Acquire::Retries=6 update \
 && apt-get -o Acquire::Retries=6 install -y --no-install-recommends g++-arm-linux-gnueabi qtbase5-dev-tools \
 && mkdir -p /debs /sysroot && cd /debs \
 && apt-get -o Acquire::Retries=6 download qtbase5-dev:armel qtdeclarative5-dev:armel \
      libgles2-mesa-dev:armel libegl1-mesa-dev:armel mesa-common-dev:armel \
 && for package in *.deb; do dpkg-deb -x "$package" /sysroot; done
