#!/bin/bash

set -e

# Configuration
COMMIT_SHA="c3c476f357f1e9768ea4e45aa5c17528449ab9ef"
PROJECT_NAME="triton"

# Paths
WORKDIR=/data/saiva/sut
TRITON_SRC=$WORKDIR/sources/triton
BUILD_DIR=$WORKDIR/builds/$PROJECT_NAME

# Build Configuration
NUM_JOBS=$(nproc)

# Parse Arguments
CLEAN=false
while (( "$#" )); do
    case "$1" in
        --clean)
            CLEAN=true
            shift
            ;;
        *)
            break
            ;;
    esac
done

# Clean if requested
if [ "$CLEAN" = true ]; then
    echo "==> Cleaning..."
    rm -rf $TRITON_SRC
fi

# Setup Directories
echo "==> Setting up directories..."
mkdir -p $WORKDIR/sources

# Clone Triton
if [ -d "$TRITON_SRC" ]; then
    echo "==> Triton directory exists, cleaning..."
    rm -rf $TRITON_SRC
fi

echo "==> Cloning Triton..."
cd $WORKDIR/sources
git clone https://github.com/triton-lang/triton.git
cd $TRITON_SRC

# Checkout specific commit
echo "==> Checking out Triton commit: $COMMIT_SHA"
git checkout $COMMIT_SHA

# Patch to skip tests
echo "==> Patching CMakeLists.txt to skip tests..."
sed -i 's/add_subdirectory(unittest)/#add_subdirectory(unittest)/' CMakeLists.txt

# Install requirements
echo "==> Installing build requirements..."
if [ -f "python/requirements.txt" ]; then
    pip install -r python/requirements.txt
fi

# Build following README instructions
echo ""
echo "==> Building Triton with sanitizers and coverage..."
cd $TRITON_SRC

# Set environment variables per README
export TRITON_BUILD_WITH_CLANG_LLD=true
export TRITON_BUILD_WITH_CCACHE=false
export MAX_JOBS=$NUM_JOBS

# Add sanitizer and coverage flags
# export CFLAGS="-fsanitize=address -fprofile-instr-generate -fcoverage-mapping"
# export CXXFLAGS="-fsanitize=address -fprofile-instr-generate -fcoverage-mapping"
# export LDFLAGS="-fsanitize=address"

export CFLAGS="-fprofile-instr-generate -fcoverage-mapping"
export CXXFLAGS="-fprofile-instr-generate -fcoverage-mapping"


echo "==> Building with flags:"
echo "  CFLAGS=$CFLAGS"
echo "  CXXFLAGS=$CXXFLAGS"
echo "  LDFLAGS=$LDFLAGS"

# Install from root (where setup.py is)
echo "==> Installing Triton (without tests)..."
pip install --no-build-isolation -e .

# Find triton-opt binary
echo ""
echo "==> Locating triton-opt..."

# Search in common locations
TRITON_OPT=$(find . ~/.triton -name "triton-opt" -type f 2>/dev/null | head -1)

# Copy to our builds directory for consistency
if [ -n "$TRITON_OPT" ]; then
    mkdir -p $BUILD_DIR/bin
    cp "$TRITON_OPT" "$BUILD_DIR/bin/"
    TRITON_OPT_FINAL="$BUILD_DIR/bin/triton-opt"
    echo "Copied to: $TRITON_OPT_FINAL"
fi

# Summary
echo ""
echo "=========================================="
echo "Triton Build Complete!"
echo "=========================================="
if [ -n "$TRITON_OPT_FINAL" ] && [ -f "$TRITON_OPT_FINAL" ]; then
    echo "triton-opt: $TRITON_OPT_FINAL"
    echo ""
    echo "Test with:"
    echo "  $TRITON_OPT_FINAL --help"
else
    echo "triton-opt: May be in build artifacts"
    echo "Search with: find ~/.triton $TRITON_SRC -name triton-opt 2>/dev/null"
fi
echo "=========================================="