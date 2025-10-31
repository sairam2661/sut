#!/bin/bash
set -e

# Configuration
PROJECT_NAME="circt"
COMMIT_SHA="e2b32a42edf7b579069ba31141ce231a0eaae36b"

# Paths
WORKDIR=/data/saiva/sut
CIRCT_SRC=$WORKDIR/sources/circt
LLVM_SRC=$CIRCT_SRC/llvm
LLVM_BUILD=$WORKDIR/builds/llvm_for_circt
CIRCT_BUILD=$WORKDIR/builds/$PROJECT_NAME

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
    rm -rf $CIRCT_SRC
    rm -rf $LLVM_BUILD
    rm -rf $CIRCT_BUILD
fi

# Setup Directories
echo "==> Setting up directories..."
mkdir -p $WORKDIR/sources
mkdir -p $LLVM_BUILD
mkdir -p $CIRCT_BUILD

# Clone CIRCT 
if [ -d "$CIRCT_SRC" ]; then
    echo "==> CIRCT directory exists, checking commit..."
    cd $CIRCT_SRC
    CURRENT_SHA=$(git rev-parse HEAD)
    if [ "$CURRENT_SHA" != "$COMMIT_SHA" ]; then
        echo "==> Checking out specific commit ($COMMIT_SHA)..."
        git fetch
        git checkout $COMMIT_SHA
    else
        echo "==> Already at correct commit ($COMMIT_SHA)"
    fi
else
    echo "==> Cloning CIRCT..."
    cd $WORKDIR/sources
    git clone https://github.com/llvm/circt.git
    cd $CIRCT_SRC
    echo "==> Checking out specific commit ($COMMIT_SHA)..."
    git checkout $COMMIT_SHA
fi

echo "==> Updating submodules..."
cd $CIRCT_SRC
git submodule update --init --recursive

# Build LLVM/MLIR
echo "==> Configuring LLVM/MLIR for CIRCT..."
cd $LLVM_BUILD

cmake -G Ninja $LLVM_SRC/llvm \
    -DLLVM_ENABLE_PROJECTS="mlir" \
    -DLLVM_TARGETS_TO_BUILD="X86;RISCV" \
    -DLLVM_ENABLE_ASSERTIONS=ON \
    -DCMAKE_BUILD_TYPE=$BUILD_TYPE \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DLLVM_ENABLE_LLD=ON

echo "==> Building LLVM/MLIR..."
ninja -j $NUM_JOBS

# Build CIRCT
echo "==> Configuring CIRCT with coverage..."
cd $CIRCT_BUILD

cmake -G Ninja $CIRCT_SRC \
    -DMLIR_DIR=$LLVM_BUILD/lib/cmake/mlir \
    -DLLVM_DIR=$LLVM_BUILD/lib/cmake/llvm \
    -DLLVM_ENABLE_ASSERTIONS=ON \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DLLVM_USE_SANITIZER="Address;Undefined" \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DLLVM_ENABLE_LLD=ON \
    -DCMAKE_C_FLAGS="-fprofile-instr-generate -fcoverage-mapping -Wno-error=pass-failed" \
    -DCMAKE_CXX_FLAGS="-fprofile-instr-generate -fcoverage-mapping -Wno-error=pass-failed"

echo "==> Building CIRCT..."
ninja -j $NUM_JOBS

echo "==> Running CIRCT tests..."
ninja check-circt

# Summary
echo ""
echo "=========================================="
echo "CIRCT Build Complete!"
echo "=========================================="
echo "circt-opt: $CIRCT_BUILD/bin/circt-opt"
echo "=========================================="