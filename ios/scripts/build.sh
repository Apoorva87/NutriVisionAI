#!/bin/bash
# NutriVisionAI Build Script
# Usage: ./scripts/build.sh [backend|apple-ai] [debug|release]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")/NutriVisionAI"

# Defaults
BUILD_TYPE="${1:-backend}"
BUILD_CONFIG="${2:-debug}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}NutriVisionAI Build Script${NC}"
echo "================================"
echo ""

# Check for xcodegen
if ! command -v xcodegen &> /dev/null; then
    echo -e "${RED}Error: xcodegen is not installed.${NC}"
    echo "Install with: brew install xcodegen"
    exit 1
fi

# Navigate to project directory
cd "$PROJECT_DIR"

# Generate Xcode project
echo -e "${YELLOW}Generating Xcode project...${NC}"
xcodegen generate

# Determine scheme and configuration
case "$BUILD_TYPE" in
    "backend")
        SCHEME="NutriVisionAI"
        case "$BUILD_CONFIG" in
            "debug")
                CONFIG="Debug"
                ;;
            "release")
                CONFIG="Release"
                ;;
            *)
                echo -e "${RED}Invalid config. Use: debug or release${NC}"
                exit 1
                ;;
        esac
        echo -e "${GREEN}Building with Backend API provider...${NC}"
        ;;
    "apple-ai")
        SCHEME="NutriVisionAI-AppleAI"
        case "$BUILD_CONFIG" in
            "debug")
                CONFIG="Debug-AppleAI"
                ;;
            "release")
                CONFIG="Release-AppleAI"
                ;;
            *)
                echo -e "${RED}Invalid config. Use: debug or release${NC}"
                exit 1
                ;;
        esac
        echo -e "${YELLOW}Note: Apple Foundation Models requires iOS 26+${NC}"
        echo -e "${GREEN}Building with Apple Foundation Models support...${NC}"
        ;;
    *)
        echo -e "${RED}Invalid build type. Use: backend or apple-ai${NC}"
        echo ""
        echo "Usage: ./scripts/build.sh [backend|apple-ai] [debug|release]"
        echo ""
        echo "Examples:"
        echo "  ./scripts/build.sh backend debug    # Backend API, Debug build"
        echo "  ./scripts/build.sh backend release  # Backend API, Release build"
        echo "  ./scripts/build.sh apple-ai debug   # Apple AI, Debug build (iOS 26+)"
        echo "  ./scripts/build.sh apple-ai release # Apple AI, Release build (iOS 26+)"
        exit 1
        ;;
esac

echo ""
echo "Scheme: $SCHEME"
echo "Configuration: $CONFIG"
echo ""

# Build the project
echo -e "${YELLOW}Building...${NC}"
xcodebuild -project NutriVisionAI.xcodeproj \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -sdk iphonesimulator \
    -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
    build

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}Build successful!${NC}"
    echo ""
    echo "To run in Xcode:"
    echo "  1. Open NutriVisionAI.xcodeproj"
    echo "  2. Select scheme: $SCHEME"
    echo "  3. Press Cmd+R to run"
else
    echo ""
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi
