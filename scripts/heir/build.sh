#!/bin/bash

# This requires LLVM 19+
set -e

# Configuration
COMMIT_SHA="a413796feb31eb6a1e70160308defe4d0250d09e"
PROJECT_NAME="heir"

# Paths
WORKDIR=/data/saiva/sut
HEIR_SRC=$WORKDIR/sources/heir
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
    rm -rf $HEIR_SRC
    rm -rf $BUILD_DIR
fi

# Setup Directories
echo "==> Setting up directories..."
mkdir -p $WORKDIR/sources
mkdir -p $BUILD_DIR/bin

# Check for Clang (required by HEIR)
if ! command -v clang &> /dev/null || ! command -v clang++ &> /dev/null; then
    echo "ERROR: Clang not found. HEIR requires Clang 19+ for building."
    echo "Please install Clang:"
    echo "  Ubuntu/Debian: sudo apt-get install clang-19 lld-19"
    echo "  RHEL/CentOS:   sudo yum install clang lld"
    echo "  Fedora:        sudo dnf install clang lld"
    echo ""
    echo "Then create symlinks (Ubuntu/Debian):"
    echo "  sudo update-alternatives --install /usr/bin/clang clang /usr/bin/clang-19 100"
    echo "  sudo update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-19 100"
    exit 1
fi

# Check Clang version
CLANG_VERSION=$(clang --version | grep -oP 'clang version \K[0-9]+' | head -1)
echo "==> Found Clang version: $CLANG_VERSION"

if [ "$CLANG_VERSION" -lt 19 ]; then
    echo "ERROR: Clang $CLANG_VERSION is too old. HEIR requires Clang 19 or newer."
    echo ""
    echo "Your system has Clang $CLANG_VERSION, which has compatibility issues with HEIR's LLVM code."
    echo ""
    echo "Please install a newer version:"
    echo "  Ubuntu/Debian:"
    echo "    sudo apt-get install clang-19 lld-19"
    echo "    sudo update-alternatives --install /usr/bin/clang clang /usr/bin/clang-19 100"
    echo "    sudo update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-19 100"
    echo ""
    echo "Or use --config=gcc to build with GCC instead (coverage won't work):"
    echo "    bazel build --config=gcc //tools:heir-opt"
    exit 1
fi

# Check for Bazel/Bazelisk
if ! command -v bazelisk &> /dev/null && ! command -v bazel &> /dev/null; then
    echo "ERROR: Neither bazel nor bazelisk found. Please install bazelisk:"
    echo "  npm install -g @bazel/bazelisk"
    echo "  OR"
    echo "  wget https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-amd64 -O /usr/local/bin/bazelisk"
    echo "  chmod +x /usr/local/bin/bazelisk"
    exit 1
fi

# Use bazelisk if available, otherwise bazel
if command -v bazelisk &> /dev/null; then
    BAZEL_CMD=bazelisk
else
    BAZEL_CMD=bazel
fi

# Clone HEIR
if [ -d "$HEIR_SRC" ]; then
    echo "==> HEIR directory exists, updating..."
    cd $HEIR_SRC
    git fetch
    git checkout $COMMIT_SHA
    git pull origin $COMMIT_SHA || true
else
    echo "==> Cloning HEIR..."
    cd $WORKDIR/sources
    git clone https://github.com/google/heir.git
    cd $HEIR_SRC
    if [ "$COMMIT_SHA" != "main" ]; then
        echo "==> Checking out HEIR commit: $COMMIT_SHA"
        git checkout $COMMIT_SHA
    fi
fi

cd $HEIR_SRC

# Force Bazel 7.x for WORKSPACE compatibility
echo "==> Configuring Bazel version for WORKSPACE compatibility..."
echo "7.4.1" > .bazelversion
echo "Set Bazel version to 7.4.1 (WORKSPACE compatible)"

# Create .bazelrc.user for coverage configurations
echo "==> Configuring coverage for Clang..."

# Check if .bazelrc exists and whether it imports .bazelrc.user
if [ -f ".bazelrc" ]; then
    if ! grep -q "try-import.*bazelrc.user" .bazelrc; then
        echo "==> Adding .bazelrc.user import to .bazelrc..."
        echo "" >> .bazelrc
        echo "# Import user-specific settings" >> .bazelrc
        echo "try-import %workspace%/.bazelrc.user" >> .bazelrc
    fi
else
    echo "WARNING: No .bazelrc file found in repository"
fi

cat > .bazelrc.user << 'EOF'
build --cxxopt=-Wno-error
build --per_file_copt=external/protobuf~.*@-Wno-error=incomplete-type
build --per_file_copt=external/protobuf~.*@-Wno-incomplete-type

# Coverage configuration
build:coverage --copt=-fprofile-instr-generate
build:coverage --copt=-fcoverage-mapping
build:coverage --linkopt=-fprofile-instr-generate
build:coverage --linkopt=-fcoverage-mapping

# UBSan configuration
build:ubsan --strip=never
build:ubsan --copt=-fsanitize=undefined
build:ubsan --copt=-O1
build:ubsan --copt=-g
build:ubsan --copt=-fno-omit-frame-pointer
build:ubsan --linkopt=-fsanitize=undefined

# Combined ASan + Coverage
build:asan-cov --config=asan
build:asan-cov --copt=-fprofile-instr-generate
build:asan-cov --copt=-fcoverage-mapping
build:asan-cov --linkopt=-fprofile-instr-generate
build:asan-cov --linkopt=-fcoverage-mapping

# Coverage only
build:fuzz-cov --strip=never
build:fuzz-cov --copt=-fprofile-instr-generate
build:fuzz-cov --copt=-fcoverage-mapping
build:fuzz-cov --linkopt=-fprofile-instr-generate
build:fuzz-cov --linkopt=-fcoverage-mapping
EOF

echo "Created .bazelrc.user with coverage configurations"

# Build heir-opt with coverage and sanitizers
echo ""
echo "==> Building heir-opt with ASan + Coverage..."

# Build with both ASan and Coverage as requested
$BAZEL_CMD build --config=asan-cov //tools:heir-opt

# Find and copy the heir-opt binary
echo ""
echo "==> Locating heir-opt binary..."

# Bazel puts binaries in bazel-bin
HEIR_OPT_SRC=$(find $HEIR_SRC/bazel-bin/tools -name "heir-opt" -type f 2>/dev/null | head -1)

if [ -z "$HEIR_OPT_SRC" ]; then
    echo "ERROR: Could not find heir-opt binary"
    echo "Searching in bazel-bin:"
    find $HEIR_SRC/bazel-bin -name "heir-opt" 2>/dev/null || echo "Not found"
    exit 1
fi

echo "Found heir-opt at: $HEIR_OPT_SRC"
cp "$HEIR_OPT_SRC" "$BUILD_DIR/bin/heir-opt"
chmod +x "$BUILD_DIR/bin/heir-opt"

# Also build heir-translate for completeness
echo ""
echo "==> Building heir-translate..."
$BAZEL_CMD build --config=asan-cov //tools:heir-translate

HEIR_TRANSLATE_SRC=$(find $HEIR_SRC/bazel-bin/tools -name "heir-translate" -type f 2>/dev/null | head -1)
if [ -n "$HEIR_TRANSLATE_SRC" ]; then
    cp "$HEIR_TRANSLATE_SRC" "$BUILD_DIR/bin/heir-translate"
    chmod +x "$BUILD_DIR/bin/heir-translate"
    echo "Copied heir-translate to: $BUILD_DIR/bin/heir-translate"
fi

# Summary
echo ""
echo "=========================================="
echo "HEIR Build Complete!"
echo "=========================================="
echo "heir-opt: $BUILD_DIR/bin/heir-opt"
if [ -f "$BUILD_DIR/bin/heir-translate" ]; then
    echo "heir-translate: $BUILD_DIR/bin/heir-translate"
fi
echo ""
echo "Test with:"
echo "  $BUILD_DIR/bin/heir-opt --help"
echo ""
if [ -n "$COMMIT_SHA" ] && [ "$COMMIT_SHA" != "main" ]; then
    echo "HEIR commit: $COMMIT_SHA"
else
    echo "HEIR branch: main"
fi
echo "=========================================="