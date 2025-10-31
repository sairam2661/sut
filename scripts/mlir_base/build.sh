#!/bin/bash

set -e

# Configuration
COMMIT_SHA="ab5eae01646e2a83356ec8fe300bf727dadc87dd"
PROJECT_NAME="mlir_base"

# Paths
WORKDIR=/data/saiva/sut
SRC_DIR=$WORKDIR/sources/llvm-project
BUILD_DIR=$WORKDIR/builds/$PROJECT_NAME

# Build Configuration
BUILD_TYPE=RelWithDebInfo
NUM_JOBS=$(nproc)

# Setup Directories
echo "==> Setting up directories..."
mkdir -p $WORKDIR/sources
mkdir -p $BUILD_DIR

# Clone/Update Source
if [ ! -d "$SRC_DIR" ]; then
    echo "==> Cloning LLVM..."
    cd $WORKDIR/sources
    git clone https://github.com/llvm/llvm-project.git
fi

cd $SRC_DIR

if [ "$(git rev-parse HEAD)" != "$COMMIT_SHA" ]; then
    echo "==> Checking out commit: $COMMIT_SHA"
    git fetch
    git checkout $COMMIT_SHA
else
    echo "==> Already at correct commit: $COMMIT_SHA"
fi

# Configure Build
echo "==> Configuring MLIR build with sanitizers and coverage..."
cd $BUILD_DIR

cmake -G Ninja $SRC_DIR/llvm \
    -DLLVM_ENABLE_PROJECTS=mlir \
    -DLLVM_BUILD_EXAMPLES=ON \
    -DLLVM_TARGETS_TO_BUILD="Native;NVPTX" \
    -DCMAKE_BUILD_TYPE=$BUILD_TYPE \
    -DLLVM_ENABLE_ASSERTIONS=ON \
    -DLLVM_USE_LINKER=/usr/bin/ld.lld \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DLLVM_USE_SANITIZER="Address;Undefined" \
    -DCMAKE_C_FLAGS="-fprofile-instr-generate -fcoverage-mapping" \
    -DCMAKE_CXX_FLAGS="-fprofile-instr-generate -fcoverage-mapping"

# Build
echo "==> Building mlir-opt..."
cmake --build . --target mlir-opt -j $NUM_JOBS

# Summary
echo ""
echo "=========================================="
echo "Build Complete!"
echo "=========================================="
echo "mlir-opt: $BUILD_DIR/bin/mlir-opt"
echo ""
echo "Test with:"
echo "  $BUILD_DIR/bin/mlir-opt --help"
echo "=========================================="
