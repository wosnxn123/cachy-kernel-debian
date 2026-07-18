FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bc \
        bindgen \
        bison \
        build-essential \
        busybox-static \
        ca-certificates \
        clang \
        cpio \
        curl \
        debhelper \
        dwarves \
        fakeroot \
        flex \
        gettext \
        gh \
        git \
        jq \
        kmod \
        libdw-dev \
        libelf-dev \
        libssl-dev \
        lintian \
        lld \
        llvm \
        pahole \
        patch \
        perl \
        pkg-config \
        python3 \
        qemu-system-x86 \
        rsync \
        rust-src \
        rustc \
        xxhash \
        xz-utils \
        zlib1g-dev \
        zstd \
    && rm -rf /var/lib/apt/lists/*
