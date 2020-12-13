#!/bin/bash

set -euxo pipefail

rustup_version=1.23.1
version=1.48.0

base=${1:-}

if [[ -z $base ]]; then
    echo "$0: need a base image"

    exit 1
fi

case $base in
co8)
    container=$(buildah from centos:8)

    initialize() {
        crun dnf install -y ca-certificates gcc
        crun dnf clean all
    }

    tag="${version}-co8"
    ;;
leap)
    container=$(buildah from opensuse/leap:15.2)

    initialize() {
        crun zypper mr --disable repo-non-oss repo-update-non-oss
        crun zypper --non-interactive --no-refresh install ca-certificates gcc10 curl
        crun zypper clean --all
    }

    tag="${version}-leap15.2"
    ;;
alpine)
    # reminder to use the musl rust if we are trying to alpine
    # if i ever bother:
    #buildah run $container apk add --no-cache ca-certificates gcc curl
    echo "$0: alpine doesn't work since i broke it. sry future me"
    exit 1
    ;;
*)
    echo "$0: unknown base image: $base"
    exit 1
esac

cleanup() {
    buildah rm $container
}

# don't leave half-baked trash around
trap "cleanup" ERR SIGINT SIGTERM

crun() {
    buildah run $container "$@"
}

cenv() {
    crun sh -c "echo \"\${$1}\""
}

# some inspiration from
# https://github.com/rust-lang/docker-rust/blob/c5461fab71272c9adca4804a73095a6642810f20/1.48.0/alpine3.11/Dockerfile
# before I decided to go off the deep end.

buildah config \
    --label maintainer="William Good <bkgood bij gmail punt com>" \
    --env RUSTUP_HOME=/usr/local/rustup \
    --env CARGO_HOME=/usr/local/cargo \
    --env PATH="/usr/local/cargo/bin:$(cenv "PATH")" \
    $container

initialize

crun curl -o rustup-init -sSf --proto =https --tlsv1.2 \
    "https://static.rust-lang.org/rustup/archive/$rustup_version/x86_64-unknown-linux-gnu/rustup-init"

crun chmod +x rustup-init

crun ./rustup-init -y --profile=minimal -q \
    --default-toolchain $version --no-modify-path

crun rm rustup-init

for x in RUSTUP_HOME CARGO_HOME; do
    crun chmod -R a+w $(cenv $x)
done

for cmd in rustup cargo rustc; do
    # causes everything to error out if we for whatever reason can't find the
    # command that should'be been installed.
    crun $cmd --version
done

buildah commit --rm $container rust
buildah tag rust rust:$tag
