#!/bin/bash
set -e

# ============================================================================
# Configuration
# ============================================================================
PROJECT_NAME="polygeist"

# Paths
WORKDIR=/data/saiva/sut
POLYGEIST_SRC=$WORKDIR/sources/polygeist
LLVM_SRC=$POLYGEIST_SRC/llvm-project
LLVM_BUILD=$WORKDIR/builds/llvm_for_polygeist
POLYGEIST_BUILD=$WORKDIR/builds/$PROJECT_NAME

# Build Configuration
BUILD_TYPE=RelWithDebInfo
NUM_JOBS=$(nproc)

# ============================================================================
# Parse Arguments
# ============================================================================
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

# ============================================================================
# Clean if requested
# ============================================================================
if [ "$CLEAN" = true ]; then
    echo "==> Cleaning..."
    rm -rf $POLYGEIST_SRC
    rm -rf $LLVM_BUILD
    rm -rf $POLYGEIST_BUILD
fi

# ============================================================================
# Setup Directories
# ============================================================================
echo "==> Setting up directories..."
mkdir -p $WORKDIR/sources
mkdir -p $LLVM_BUILD
mkdir -p $POLYGEIST_BUILD

# ============================================================================
# Clone Polygeist (with recursive submodules)
# ============================================================================
if [ -d "$POLYGEIST_SRC" ]; then
    echo "==> Polygeist directory exists, updating..."
    cd $POLYGEIST_SRC
    git fetch
    git pull || true
    git submodule update --init --recursive
else
    echo "==> Cloning Polygeist with submodules..."
    cd $WORKDIR/sources
    git clone --recursive https://github.com/llvm/Polygeist polygeist
    cd $POLYGEIST_SRC
fi

# ============================================================================
# Build LLVM/MLIR/Clang (Step 1)
# ============================================================================
echo "==> Configuring LLVM/MLIR/Clang for Polygeist..."
cd $LLVM_BUILD

cmake -G Ninja $LLVM_SRC/llvm \
    -DLLVM_ENABLE_PROJECTS="mlir;clang" \
    -DLLVM_TARGETS_TO_BUILD="host" \
    -DLLVM_ENABLE_ASSERTIONS=ON \
    -DCMAKE_BUILD_TYPE=$BUILD_TYPE \
    -DLLVM_USE_LINKER=lld

echo "==> Building LLVM/MLIR/Clang..."
ninja -j $NUM_JOBS

echo "==> Testing MLIR..."
ninja check-mlir

# ============================================================================
# Build Polygeist (Step 2)
# ============================================================================
echo "==> Configuring Polygeist with coverage..."
cd $POLYGEIST_BUILD

cmake -G Ninja $POLYGEIST_SRC \
    -DMLIR_DIR=$LLVM_BUILD/lib/cmake/mlir \
    -DCLANG_DIR=$LLVM_BUILD/lib/cmake/clang \
    -DLLVM_TARGETS_TO_BUILD="host" \
    -DLLVM_ENABLE_ASSERTIONS=ON \
    -DCMAKE_BUILD_TYPE=$BUILD_TYPE \
    -DPOLYGEIST_USE_LINKER=lld \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_C_FLAGS="-fprofile-instr-generate -fcoverage-mapping -Wno-error=pass-failed" \
    -DCMAKE_CXX_FLAGS="-fprofile-instr-generate -fcoverage-mapping -Wno-error=pass-failed"

echo "==> Building Polygeist..."
ninja -j $NUM_JOBS

echo "==> Running Polygeist tests..."
ninja check-polygeist-opt
ninja check-cgeist

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "=========================================="
echo "Polygeist Build Complete!"
echo "=========================================="
echo "polygeist-opt: $POLYGEIST_BUILD/bin/polygeist-opt"
echo "cgeist: $POLYGEIST_BUILD/bin/cgeist"
echo "mlir-clang: $POLYGEIST_BUILD/bin/mlir-clang"
echo "LLVM build: $LLVM_BUILD"
echo "Polygeist build: $POLYGEIST_BUILD"
echo ""
echo "Built WITH: Coverage instrumentation"
echo ""
echo "Coverage usage:"
echo "  export LLVM_PROFILE_FILE=\$PWD/coverage/%p.profraw"
echo ""
echo "Test commands:"
echo "  ninja check-polygeist-opt  # Tests in polygeist-opt"
echo "  ninja check-cgeist         # Tests in cgeist"
echo "=========================================="