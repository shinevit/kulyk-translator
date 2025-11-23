#!/bin/bash
set -e

# Function to extract target from arguments
get_target() {
    local args=("$@")
    for ((i=0; i<${#args[@]}; i++)); do
        if [[ "${args[i]}" == "--target" ]]; then
            echo "${args[i+1]}"
            return
        elif [[ "${args[i]}" == --target=* ]]; then
            echo "${args[i]#*=}"
            return
        fi
    done
}

TARGET=$(get_target "$@")

if [[ -z "$TARGET" ]]; then
    echo "Error: No target specified"
    exit 1
fi

case "$TARGET" in
    x86_64-unknown-linux-gnu|aarch64-unknown-linux-gnu)
        # Check if the multi-arch builder image already exists
        if docker image inspect kulyk-builder:latest >/dev/null 2>&1; then
            echo "Multi-arch builder image already exists, skipping build..."
        else
            echo "Building multi-arch image for Linux (x86_64 and ARM64)..."
            # docker buildx build --platform linux/amd64,linux/arm64 --target builder -t kulyk-builder:latest --load .
            # Build a full image for build and running
            docker buildx build --platform linux/amd64,linux/arm64 -t kulyk-builder:latest --load .
        fi
        
        if [[ "$TARGET" == "x86_64-unknown-linux-gnu" ]]; then
            PLATFORM="linux/amd64"
        else
            PLATFORM="linux/arm64"
        fi
        
        echo "Extracting binary for $PLATFORM..."
        # Create a container to extract the binary
        CONTAINER_ID=$(docker create --platform "$PLATFORM" kulyk-builder:latest)
        
        # Ensure target directory exists
        mkdir -p "target/$TARGET/release"
        
        # Copy binary
        # docker cp "$CONTAINER_ID":/tmp/kulyk "target/$TARGET/release/kulyk"
        docker cp "$CONTAINER_ID":/app/kulyk-translator "target/$TARGET/release/kulyk"
        
        # Cleanup
        docker rm "$CONTAINER_ID"
        ;;
    aarch64-apple-darwin)
        echo "Building for Apple Silicon ($TARGET) with Metal support..."
        # Use rustup to find the correct binaries
        RUSTC_BIN=$(rustup which rustc)
        CARGO_BIN=$(rustup which cargo)
        # Enable Metal feature for GPU acceleration on Apple Silicon
        env RUSTC="$RUSTC_BIN" "$CARGO_BIN" build --release --target "$TARGET" --features metal
        strip "target/$TARGET/release/kulyk"
        ;;
    x86_64-apple-darwin)
        echo "Building for Intel Mac ($TARGET) with native optimizations..."
        # Use rustup to find the correct binaries
        RUSTC_BIN=$(rustup which rustc)
        CARGO_BIN=$(rustup which cargo)
        # Use native CPU optimizations for Intel Macs (Metal support is limited)
        env RUSTC="$RUSTC_BIN" "$CARGO_BIN" build --release --target "$TARGET" --features native
        strip "target/$TARGET/release/kulyk"
        ;;
    *)
        echo "Error: Unsupported target $TARGET"
        exit 1
        ;;
esac
