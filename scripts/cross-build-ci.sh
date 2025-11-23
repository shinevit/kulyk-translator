#!/bin/bash
set -e

# CI/CD-specific build script that pulls Docker image from GHCR instead of building locally
# This script is used by GoReleaser in GitHub Actions

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
        IMAGE_NAME="kulyk-builder:latest"
        
        # In CI, the image should already be pulled and tagged by the workflow
        # Only pull if running locally and image doesn't exist
        if ! docker image inspect "$IMAGE_NAME" > /dev/null 2>&1; then
            if [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" ]]; then
                echo "Error: Image $IMAGE_NAME not found in CI environment"
                echo "The workflow should have pulled and tagged it already"
                exit 1
            else
                echo "Image not found locally, pulling from GHCR..."
                GHCR_IMAGE="ghcr.io/egorsmkv/kulyk-rust:latest"
                
                if docker pull "$GHCR_IMAGE"; then
                    echo "Successfully pulled $GHCR_IMAGE"
                    docker tag "$GHCR_IMAGE" "$IMAGE_NAME"
                else
                    echo "Error: Failed to pull image from GHCR"
                    exit 1
                fi
            fi
        fi
        
        if [[ "$TARGET" == "x86_64-unknown-linux-gnu" ]]; then
            PLATFORM="linux/amd64"
        else
            PLATFORM="linux/arm64"
        fi
        
        echo "Extracting binary for $PLATFORM..."
        # Create a container to extract the binary
        CONTAINER_ID=$(docker create --platform "$PLATFORM" "$IMAGE_NAME")
        
        # Ensure target directory exists
        mkdir -p "target/$TARGET/release"
        
        # Copy binary from the runner stage (final image)
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
