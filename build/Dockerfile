# Reproducible build environment for sshk's dropbearmulti.
# Produces a fully static, soft-float ARM binary suitable for jailbroken
# Kindles, and smoke-tests it under QEMU before publishing it to /out.
#
# Everything is pinned: Debian bookworm-slim + gcc-arm-linux-gnueabi from
# Debian archives, musl 1.2.5 from musl.libc.org, Dropbear version passed
# as an argument (default pinned in extensions/sshk/DROPBEAR_VERSION).
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        bzip2 \
        xz-utils \
        make \
        file \
        gcc-arm-linux-gnueabi \
        qemu-user-static \
    && rm -rf /var/lib/apt/lists/*

COPY container-build.sh /usr/local/bin/container-build.sh
RUN chmod +x /usr/local/bin/container-build.sh

WORKDIR /tmp
ENTRYPOINT ["/usr/local/bin/container-build.sh"]
