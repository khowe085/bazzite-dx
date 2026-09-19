# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

# Base Image
FROM ghcr.io/ublue-os/bazzite-dx:stable@sha256:698d351d7c256ace7133a2679d1c576ccab29f88adcd62326ee42fadca05bbc5

# Eden AppImage flavour to ship: amd64 | steamdeck | rog-ally | legacy, each as clang-pgo or gcc-standard
ARG EDEN_VARIANT=amd64-clang-pgo

### MODIFICATIONS
## build.sh lays down system_files/ and runs build_files/NN-*.sh in order; the last step
## (90-verify.sh) fails the build if anything expected is missing.

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    EDEN_VARIANT="${EDEN_VARIANT}" bash /ctx/build.sh

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
