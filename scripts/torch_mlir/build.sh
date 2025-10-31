#!/bin/bash

set -e

# Configuration
COMMIT_SHA="55c638e8a9b808ccde1109d8cbeb87fd56a71259"
PROJECT_NAME="torch_mlir"

# Paths
WORKDIR=/data/saiva/sut
SHARED_LLVM_SRC=$WORKDIR/sources/llvm-project  # Reuse shared LLVM source
TORCH_MLIR_SRC=$WORKDIR/sources/torch-mlir
LLVM_BUILD_DIR=$WORKDIR/builds/llvm_for_torch_mlir
TORCH_BUILD_DIR=$WORKDIR/builds/$PROJECT_NAME

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
    rm -rf $TORCH_BUILD_DIR
fi

# Setup Directories
echo "==> Setting up directories..."
mkdir -p $WORKDIR/sources
mkdir -p $LLVM_BUILD_DIR

# Clone Torch-MLI
if [ -d "$TORCH_MLIR_SRC" ]; then
    echo "==> Torch-MLIR directory exists, updating..."
    cd $TORCH_MLIR_SRC
    git fetch
    # Reset any previous patches
    git checkout .
else
    echo "==> Cloning Torch-MLIR..."
    cd $WORKDIR/sources
    git clone https://github.com/llvm/torch-mlir.git
    cd $TORCH_MLIR_SRC
fi

if [ "$(git rev-parse HEAD)" != "$COMMIT_SHA" ]; then
    echo "==> Checking out Torch-MLIR commit: $COMMIT_SHA"
    git checkout $COMMIT_SHA
else
    echo "==> Already at correct Torch-MLIR commit"
fi

echo "==> Initializing submodules..."
git submodule update --init --recursive

# Read the LLVM commit that torch-mlir expects
REQUIRED_LLVM_COMMIT=$(cd externals/llvm-project && git rev-parse HEAD)
echo "==> Torch-MLIR requires LLVM commit: $REQUIRED_LLVM_COMMIT"

# Patch torch-mlir to skip tests
echo "==> Patching torch-mlir to skip test directory and test targets..."
cd $TORCH_MLIR_SRC

# Create a backup
cp CMakeLists.txt CMakeLists.txt.backup

# Remove test-related lines
grep -v "add_subdirectory(test)" CMakeLists.txt.backup | \
grep -v "add_custom_target(check-torch-mlir-all)" | \
grep -v "add_dependencies(check-torch-mlir-all check-torch-mlir)" > CMakeLists.txt

echo "==> Patched CMakeLists.txt"

# Setup Shared LLVM Source at the right commit
if [ ! -d "$SHARED_LLVM_SRC" ]; then
    echo "==> Cloning LLVM (shared source)..."
    cd $WORKDIR/sources
    git clone https://github.com/llvm/llvm-project.git
fi

cd $SHARED_LLVM_SRC

# Checkout the LLVM commit torch-mlir needs
if [ "$(git rev-parse HEAD)" != "$REQUIRED_LLVM_COMMIT" ]; then
    echo "==> Checking out LLVM commit: $REQUIRED_LLVM_COMMIT"
    git fetch
    git checkout $REQUIRED_LLVM_COMMIT
else
    echo "==> Already at correct LLVM commit: $REQUIRED_LLVM_COMMIT"
fi

# Build LLVM with torch-mlir as external project
echo "==> Building LLVM with torch-mlir as external project..."
cd $LLVM_BUILD_DIR

cmake -G Ninja $SHARED_LLVM_SRC/llvm \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DLLVM_ENABLE_PROJECTS=mlir \
    -DLLVM_EXTERNAL_PROJECTS="torch-mlir" \
    -DLLVM_EXTERNAL_TORCH_MLIR_SOURCE_DIR=$TORCH_MLIR_SRC \
    -DLLVM_TARGETS_TO_BUILD="host;NVPTX" \
    -DLLVM_ENABLE_ASSERTIONS=ON \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DLLVM_USE_LINKER=lld \
    -DMLIR_ENABLE_BINDINGS_PYTHON=OFF \
    -DTORCH_MLIR_ENABLE_PYTORCH_EXTENSIONS=OFF \
    -DTORCH_MLIR_ENABLE_STABLEHLO=OFF \
    -DLLVM_USE_SANITIZER="Address;Undefined" \
    -DCMAKE_C_FLAGS="-fprofile-instr-generate -fcoverage-mapping" \
    -DCMAKE_CXX_FLAGS="-fprofile-instr-generate -fcoverage-mapping"

echo "==> Building torch-mlir-opt..."
cmake --build . --target torch-mlir-opt -j $NUM_JOBS

# Restore torch-mlir CMakeLists.txt
echo "==> Restoring torch-mlir CMakeLists.txt..."
cd $TORCH_MLIR_SRC
mv CMakeLists.txt.backup CMakeLists.txt

# Summary
echo ""
echo "=========================================="
echo "Torch-MLIR Build Complete!"
echo "=========================================="
echo "torch-mlir-opt: $LLVM_BUILD_DIR/bin/torch-mlir-opt"
echo ""
echo "Test with:"
echo "  $LLVM_BUILD_DIR/bin/torch-mlir-opt --help"
echo "=========================================="