#!/bin/bash

set -e

# Configuration
ONNX_COMMIT_SHA="d70cb7ac9e0dd2327413a5c01e225b2efabf8bc4"
LLVM_COMMIT_SHA="b2cdf3cc4c08729d0ff582d55e40793a20bbcdcc"
PROJECT_NAME="onnx_mlir"

# Paths
WORKDIR=/data/saiva/sut
SHARED_LLVM_SRC=$WORKDIR/sources/llvm-project
ONNX_SRC_DIR=$WORKDIR/sources/onnx-mlir
LLVM_BUILD_DIR=$WORKDIR/builds/llvm_for_onnx
ONNX_BUILD_DIR=$WORKDIR/builds/$PROJECT_NAME

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
    echo "==> Cleaning build directories..."
    rm -rf $LLVM_BUILD_DIR
    rm -rf $ONNX_BUILD_DIR
fi

# Setup Directories
echo "==> Setting up directories..."
mkdir -p $WORKDIR/sources
mkdir -p $LLVM_BUILD_DIR
mkdir -p $ONNX_BUILD_DIR

# Setup Shared LLVM Source
if [ ! -d "$SHARED_LLVM_SRC" ]; then
    echo "==> Cloning LLVM (shared source)..."
    cd $WORKDIR/sources
    git clone https://github.com/llvm/llvm-project.git
fi

cd $SHARED_LLVM_SRC

# Checkout LLVM commit needed for ONNX-MLIR
if [ "$(git rev-parse HEAD)" != "$LLVM_COMMIT_SHA" ]; then
    echo "==> Checking out LLVM commit: $LLVM_COMMIT_SHA"
    git checkout $LLVM_COMMIT_SHA
else
    echo "==> Already at correct LLVM commit: $LLVM_COMMIT_SHA"
fi

# Build LLVM for ONNX-MLIR
echo "==> Building LLVM for ONNX-MLIR..."
cd $LLVM_BUILD_DIR

cmake -G Ninja $SHARED_LLVM_SRC/llvm \
    -DLLVM_ENABLE_PROJECTS=mlir \
    -DLLVM_TARGETS_TO_BUILD="host" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_ENABLE_ASSERTIONS=ON \
    -DLLVM_ENABLE_RTTI=ON \
    -DLLVM_ENABLE_LIBEDIT=OFF \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DLLVM_USE_LINKER=lld

echo "==> Building LLVM..."
cmake --build . -j $NUM_JOBS

echo "==> Running MLIR tests..."
cmake --build . --target check-mlir

# Clone ONNX-MLIR
if [ -d "$ONNX_SRC_DIR" ]; then
    echo "==> ONNX-MLIR directory exists, updating..."
    cd $ONNX_SRC_DIR
    git fetch
else
    echo "==> Cloning ONNX-MLIR..."
    cd $WORKDIR/sources
    git clone https://github.com/onnx/onnx-mlir.git
    cd $ONNX_SRC_DIR
fi

# Checkout specific commit
if [ "$(git rev-parse HEAD)" != "$ONNX_COMMIT_SHA" ]; then
    echo "==> Checking out ONNX-MLIR commit: $ONNX_COMMIT_SHA"
    git checkout $ONNX_COMMIT_SHA
else
    echo "==> Already at correct ONNX-MLIR commit"
fi

# Initialize submodules
echo "==> Updating submodules..."
git submodule update --init --recursive

# Build ONNX-MLIR with Sanitizers and Coverage
MLIR_DIR=$LLVM_BUILD_DIR/lib/cmake/mlir

echo "==> Building ONNX-MLIR with sanitizers and coverage..."
cd $ONNX_BUILD_DIR

cmake -G Ninja $ONNX_SRC_DIR \
    -DMLIR_DIR=${MLIR_DIR} \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DLLVM_USE_SANITIZER="Address;Undefined" \
    -DCMAKE_C_FLAGS="-fprofile-instr-generate -fcoverage-mapping" \
    -DCMAKE_CXX_FLAGS="-fprofile-instr-generate -fcoverage-mapping" \
    -DLLVM_USE_LINKER=lld \

echo "==> Building ONNX-MLIR..."
cmake --build . --target onnx-mlir-opt -j $(nproc)

# Summary
echo ""
echo "=========================================="
echo "ONNX-MLIR Build Complete!"
echo "=========================================="
echo "onnx-mlir-opt: $ONNX_BUILD_DIR/bin/onnx-mlir-opt"
echo ""
echo "Test with:"
echo "  $ONNX_BUILD_DIR/bin/onnx-mlir-opt --help"
echo "=========================================="