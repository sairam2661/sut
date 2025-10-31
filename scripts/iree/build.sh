#!/bin/bash

set -e

# Configuration
COMMIT_SHA="afe01bda52cf977a8e371caf147e38a38542622d"
PROJECT_NAME="iree"

# Paths
WORKDIR=/data/saiva/sut
IREE_SRC=$WORKDIR/sources/iree
BUILD_DIR=$WORKDIR/builds/$PROJECT_NAME

# Build Configuration
BUILD_TYPE=RelWithDebInfo
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
    rm -rf $IREE_SRC
    rm -rf $BUILD_DIR
fi

# Setup Directories
echo "==> Setting up directories..."
mkdir -p $WORKDIR/sources
mkdir -p $BUILD_DIR

# Clone IREE
if [ -d "$IREE_SRC" ]; then
    echo "==> IREE directory exists, updating..."
    cd $IREE_SRC
    git fetch
    git checkout $COMMIT_SHA
    git pull || true
else
    echo "==> Cloning IREE..."
    cd $WORKDIR/sources
    git clone https://github.com/iree-org/iree.git
    cd $IREE_SRC
    if [ "$COMMIT_SHA" != "main" ]; then
        git checkout $COMMIT_SHA
    fi
fi

cd $IREE_SRC
git submodule update --init

# Configure Build
echo "==> Configuring IREE build with coverage only..."
cd $BUILD_DIR

cmake -G Ninja $IREE_SRC \
-DCMAKE_BUILD_TYPE=$BUILD_TYPE \
-DCMAKE_C_COMPILER=clang \
-DCMAKE_CXX_COMPILER=clang++ \
-DIREE_ENABLE_LLD=ON \
-DIREE_ENABLE_ASSERTIONS=ON \
-DIREE_BUILD_COMPILER=ON \
-DIREE_ENABLE_ASAN=ON \
-DCMAKE_C_FLAGS="-fprofile-instr-generate -fcoverage-mapping -Wno-error=pass-failed" \
-DCMAKE_CXX_FLAGS="-fprofile-instr-generate -fcoverage-mapping -Wno-error=pass-failed"

# Build
echo "==> Building iree-compile and iree-opt..."
cmake --build . --target iree-compile iree-opt -j $NUM_JOBS

# Summary
echo ""
echo "=========================================="
echo "IREE Build Complete!"
echo "=========================================="
echo "iree-compile: $BUILD_DIR/tools/iree-compile"
echo "iree-opt: $BUILD_DIR/tools/iree-opt"
echo "=========================================="