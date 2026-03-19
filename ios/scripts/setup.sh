#!/bin/bash
# NutriVisionAI Setup Script
# Run this first to set up the development environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")/NutriVisionAI"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════╗"
echo "║     NutriVisionAI iOS Setup Script        ║"
echo "╚═══════════════════════════════════════════╝"
echo -e "${NC}"

# Check for Homebrew
echo -e "${BLUE}Checking prerequisites...${NC}"

if ! command -v brew &> /dev/null; then
    echo -e "${RED}Homebrew not found. Installing...${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
echo -e "${GREEN}✓${NC} Homebrew installed"

# Check for Xcode
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}Xcode Command Line Tools not found.${NC}"
    echo "Please install Xcode from the App Store and run:"
    echo "  xcode-select --install"
    exit 1
fi
echo -e "${GREEN}✓${NC} Xcode Command Line Tools installed"

# Check Xcode version
XCODE_VERSION=$(xcodebuild -version | head -1 | awk '{print $2}')
echo -e "${GREEN}✓${NC} Xcode version: $XCODE_VERSION"

# Install xcodegen
if ! command -v xcodegen &> /dev/null; then
    echo -e "${YELLOW}Installing xcodegen...${NC}"
    brew install xcodegen
fi
echo -e "${GREEN}✓${NC} xcodegen installed"

# Navigate to project directory
cd "$PROJECT_DIR"

# Generate Xcode project
echo ""
echo -e "${YELLOW}Generating Xcode project...${NC}"
xcodegen generate

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Xcode project generated"
else
    echo -e "${RED}Failed to generate Xcode project${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo -e "${BLUE}Available build configurations:${NC}"
echo ""
echo "  1. Backend API (default, iOS 17+)"
echo "     - Uses your server for AI analysis"
echo "     - Works with any AI provider configured on server"
echo "     ./scripts/build.sh backend debug"
echo ""
echo "  2. Apple Foundation Models (iOS 26+)"
echo "     - On-device AI using Apple's models"
echo "     - No server required for image analysis"
echo "     ./scripts/build.sh apple-ai debug"
echo ""
echo -e "${BLUE}Quick start:${NC}"
echo ""
echo "  1. Open in Xcode:"
echo "     open NutriVisionAI.xcodeproj"
echo ""
echo "  2. Select your target device/simulator"
echo ""
echo "  3. Choose scheme:"
echo "     - NutriVisionAI (Backend API)"
echo "     - NutriVisionAI-AppleAI (Apple Foundation Models)"
echo ""
echo "  4. Press Cmd+R to build and run"
echo ""
echo -e "${YELLOW}Note: For device testing with backend, update the server URL${NC}"
echo "      in Settings > Connection to point to your Mac's IP address."
