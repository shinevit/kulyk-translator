download_models:
    mkdir -p models/
    wget -O "models/kulyk-uk-en.Q8_0.gguf" "https://huggingface.co/Yehor/kulyk-uk-en/resolve/main/kulyk-uk-en-q8_0.gguf"
    wget -O "models/kulyk-en-uk.Q8_0.gguf" "https://huggingface.co/Yehor/kulyk-en-uk/resolve/main/kulyk-en-uk-q8_0.gguf"

build_release:
    cargo build --release

# Download models only if they don't exist
ensure_models:
    #!/usr/bin/env bash
    if [ ! -f "models/kulyk-uk-en.Q8_0.gguf" ] || [ ! -f "models/kulyk-en-uk.Q8_0.gguf" ]; then
        echo "Models not found, downloading..."
        just download_models
    else
        echo "Models already exist, skipping download."
    fi

run: build_release ensure_models
    ./target/release/kulyk --port 3021 --verbose --threads 1 --threads-batch 1 --n-len 1024 --model-path-ue models/kulyk-uk-en.Q8_0.gguf --model-path-eu models/kulyk-en-uk.Q8_0.gguf

# Build custom Docker images for cross-compilation
build_cross_images:
    docker build --platform=linux/amd64 -f dockerfiles/Dockerfile.x86_64-unknown-linux-gnu -t x86_64-unknown-linux-gnu:my-edge .
    docker build --platform=linux/amd64 -f dockerfiles/Dockerfile.aarch64-unknown-linux-gnu -t aarch64-unknown-linux-gnu:my-edge .

# Cross-compile for Linux x86_64
cross_linux_x64:
    ./scripts/cross-build.sh --target x86_64-unknown-linux-gnu

# Cross-compile for Linux ARM64
cross_linux_arm64:
    ./scripts/cross-build.sh --target aarch64-unknown-linux-gnu

# Build for macOS x86_64 (Intel) with native (CPU) optimizations
cross_macos_x64:
    ./scripts/cross-build.sh --target x86_64-apple-darwin

# Build for macOS ARM64 (Apple Silicon) with Metal support
cross_macos_arm64:
    ./scripts/cross-build.sh --target aarch64-apple-darwin

# Build for all defined targets using GoReleaser
cross_all:
    goreleaser build --clean --snapshot --id kulyk-all --timeout 60m

