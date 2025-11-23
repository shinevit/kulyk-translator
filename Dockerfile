# ==============================================================================
# Multi-Arch Dockerfile for kulyk-rust
# Supports building for linux/amd64 and linux/arm64 platforms.
#
# Usage:
#
#   docker buildx create --use  # (if not already set up)
#   docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/egorsmkv/kulyk-rust:latest --push .
#
# Load built images to localhost for both architectures:
#
#   docker buildx build --platform linux/amd64 -t kulyk-rust:latest-amd64 . --load
#   docker buildx build --platform linux/arm64 -t kulyk-rust:latest-arm64 . --load
#
# Run:
#
#   docker run --rm --platform linux/amd64 -p 3000:3000 kulyk-rust:latest-amd64
#   docker run --rm --platform linux/arm64 -p 3000:3000 kulyk-rust:latest-arm64
#
# This produces a multi-arch manifest that can be pushed to a registry like GHCR.
# The builder stage compiles the Rust application using cross-compilation toolchains
# and selects the appropriate binary based on TARGETARCH.
# ==============================================================================

# ==============================================================================
# Stage 1: Builder
# Compiles the Rust application for the target architecture.
# ==============================================================================
FROM --platform=$BUILDPLATFORM rust:1.91-slim-bookworm AS builder

WORKDIR /usr/src/kulyk-rust

# Install required build tools: clang, libclang-dev, and cross compilers
RUN apt-get update && apt-get install -y --no-install-recommends \
    clang \
    libclang-dev \
    cmake \
    make \
    pkg-config \
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu binutils-aarch64-linux-gnu \
    gcc-x86-64-linux-gnu g++-x86-64-linux-gnu binutils-x86-64-linux-gnu \
    && rm -rf /var/lib/apt/lists/*

# Cache Cargo metadata
COPY Cargo.toml Cargo.lock ./
# Copy source code and UI file
COPY src ./src
COPY ui.html ./

ARG TARGETARCH
RUN rustup component add rustfmt;
RUN set -eux; \
    if [ "$TARGETARCH" = "arm64" ]; then \
    rustup target add aarch64-unknown-linux-gnu; \
    export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc; \
    export CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc; \
    export CXX_aarch64_unknown_linux_gnu=aarch64-linux-gnu-g++; \
    export CFLAGS_aarch64_unknown_linux_gnu="-march=armv8.2-a+fp16+dotprod"; \
    export CXXFLAGS_aarch64_unknown_linux_gnu="-march=armv8.2-a+fp16+dotprod"; \
    cargo build --release --no-default-features --target aarch64-unknown-linux-gnu; \
    aarch64-linux-gnu-strip target/aarch64-unknown-linux-gnu/release/kulyk; \
    cp target/aarch64-unknown-linux-gnu/release/kulyk /tmp/; \
    rm -rf target; \
    elif [ "$TARGETARCH" = "amd64" ]; then \
    rustup target add x86_64-unknown-linux-gnu; \
    export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER=x86_64-linux-gnu-gcc; \
    export CC_x86_64_unknown_linux_gnu=x86_64-linux-gnu-gcc; \
    export CXX_x86_64_unknown_linux_gnu=x86_64-linux-gnu-g++; \
    cargo build --release --no-default-features --target x86_64-unknown-linux-gnu; \
    x86_64-linux-gnu-strip target/x86_64-unknown-linux-gnu/release/kulyk; \
    cp target/x86_64-unknown-linux-gnu/release/kulyk /tmp/; \
    rm -rf target; \
    else \
    echo "Unsupported architecture: $TARGETARCH" && exit 1; \
    fi

# ==============================================================================
# Stage 2: Downloader
# Downloads the GGUF models using temporary dependencies (wget, ca-certificates).
# ==============================================================================
FROM debian:bookworm-slim AS downloader

# Install temporary dependencies for downloading models.
RUN apt-get update && apt-get install -y \
    wget \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Download models to a staging directory.
RUN mkdir -p /download/models && \
    wget -O /download/models/kulyk-uk-en.gguf "https://huggingface.co/mradermacher/kulyk-uk-en-GGUF/resolve/main/kulyk-uk-en.Q8_0.gguf" && \
    wget -O /download/models/kulyk-en-uk.gguf "https://huggingface.co/mradermacher/kulyk-en-uk-GGUF/resolve/main/kulyk-en-uk.Q8_0.gguf"

# ==============================================================================
# Stage 3: Runner
# Creates the final minimal image with runtime dependencies, models, and the
# architecture-specific binary. Runs as non-root user for security.
# ==============================================================================
FROM debian:bookworm-slim AS runner

# Add metadata labels for better image introspection.
LABEL maintainer="egorsmkv"
LABEL org.opencontainers.image.source="https://github.com/egorsmkv/kulyk-rust"
LABEL org.opencontainers.image.description="A translator application using local models, supporting Ukrainian and English."

# Install runtime dependencies (libgomp1 for OpenMP support in llama.cpp).
# ca-certificates omitted as the app uses local models and has no outbound HTTPS needs.
RUN apt-get update && apt-get install -y \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy models from the downloader stage.
COPY --from=downloader --chown=1000:1000 /download/models /app/models

# Create a non-root user for running the container (principle of least privilege).
# UID 1000 is standard for non-root; home dir set to /app for simplicity.
RUN groupadd -g 1000 appuser && \
    useradd -u 1000 -g appuser -m -d /app appuser && \
    chown -R appuser:appuser /app

# Copy the compiled binary from the builder stage
COPY --from=builder /tmp/kulyk /app/kulyk-translator

# Set permissions and ownership
RUN chown appuser:appuser /app/kulyk-translator && \
    chmod 755 /app/kulyk-translator

# Switch to non-root user.
USER appuser

# Expose the port the server listens on.
EXPOSE 3000

# Set the entrypoint to run the translation server.
CMD ["./kulyk-translator", "--verbose", "--n-len", "1024", "--model-path-ue", "/app/models/kulyk-uk-en.gguf", "--model-path-eu", "/app/models/kulyk-en-uk.gguf"]
