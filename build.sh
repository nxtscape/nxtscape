#!/usr/bin/env bash

# ==========================================================================
# NXTscape Browser Build Script
# ==========================================================================
# Usage: ./build.sh [options] [architecture]
#
# Options:
#   -r    Build release version (default is debug build)
#   -n    Non-interactive mode (use all defaults, no prompts)
#
# Architecture:
#   arm64  Build for Apple Silicon (default)
#   x64    Build for Intel processors
#
# Examples:
#   ./build.sh              # Debug build for arm64
#   ./build.sh -r           # Release build for arm64
#   ./build.sh x64          # Debug build for x64
#   ./build.sh -r x64       # Release build for x64
#   ./build.sh -n           # Debug build with all defaults (no prompts)
#   ./build.sh -nr          # Release build with all defaults (no prompts)
# ==========================================================================

# Exit immediately if a command fails (e), treat unset variables as errors (u),
# and print commands before execution (x)
set -eux

# Build script for local macOS environment

# Some path variables
_root_dir=$(dirname $(greadlink -f $0)) # Gets the absolute path of the script directory
_src_dir="$_root_dir/build/src/"        # Chromium source code directory
_out_dir="Default"

chromium_version=$(cat "$_root_dir/scripts/chromium_version.txt")

# Function to copy icons from resources to the Chromium theme directory
copy_icons() {
  local src_dir="$1"
  local chromium_theme_dir="$2"

  echo "Copying icon files to Chromium theme directory: $chromium_theme_dir"

  if [ -d "$src_dir" ]; then
    # Main PNG files
    echo "Copying PNG files..."
    cp -f "$src_dir/"*.png "$chromium_theme_dir/"

    # SVG and AI files
    echo "Copying SVG and AI files..."
    cp -f "$src_dir/"*.svg "$chromium_theme_dir/"
    cp -f "$src_dir/"*.ai "$chromium_theme_dir/"

    # Copy subdirectories
    echo "Copying platform-specific icons..."

    # Mac icons
    if [ -d "$src_dir/mac" ]; then
      mkdir -p "$chromium_theme_dir/mac"
      cp -f "$src_dir/mac/"* "$chromium_theme_dir/mac/"
    fi

    # Windows icons
    if [ -d "$src_dir/win" ]; then
      mkdir -p "$chromium_theme_dir/win"
      cp -rf "$src_dir/win/"* "$chromium_theme_dir/win/"
    fi

    # Linux icons
    if [ -d "$src_dir/linux" ]; then
      mkdir -p "$chromium_theme_dir/linux"
      cp -f "$src_dir/linux/"* "$chromium_theme_dir/linux/"
    fi

    # ChromeOS icons
    if [ -d "$src_dir/chromeos" ]; then
      mkdir -p "$chromium_theme_dir/chromeos"
      cp -f "$src_dir/chromeos/"* "$chromium_theme_dir/chromeos/"
    fi

    echo "Icon files copied successfully."
  else
    echo "Warning: Icon source directory $src_dir not found. Skipping icon copy step."
  fi
}

# Parse command line options
release=false         # Default is debug build
non_interactive=false # Default is interactive mode
while getopts 'rn' OPTION; do
  case "$OPTION" in
  r)
    release=true # -r option enables release build
    ;;
  n)
    non_interactive=true # -n option enables non-interactive mode
    ;;
  esac
done

shift "$(($OPTIND - 1))" # Shift positional parameters to access non-option arguments

_arch=${1:-arm64} # Set build architecture, default to arm64 if not specified

# Variables for build steps - will be prompted
# Initialize to false so pressing Enter means "No"
should_apply_patches=false
should_sign_package=false
should_clean_build=false
should_reset_git=false
should_clean_git=false

if [ "$non_interactive" = true ]; then
  should_apply_patches=true
  should_sign_package=true
  should_clean_build=true
  should_reset_git=true
  should_clean_git=true
fi

# Handle interactive vs non-interactive mode
if [ "$non_interactive" = false ]; then
  read -p "Clean previous build artifacts (out/ directory)? (y/N). Press enter for NO: " -r reply
  if [[ "$reply" =~ ^[Yy]$ ]]; then
    should_clean_build=true
  fi
  read -p "Apply patches? (y/N). Press enter for NO: " -r reply
  if [[ "$reply" =~ ^[Yy]$ ]]; then
    should_apply_patches=true
  fi
  read -p "Sign and package the application after build? (y/N). Press enter for NO: " -r reply
  if [[ "$reply" =~ ^[Yy]$ ]]; then
    should_sign_package=true
  fi
  read -p "Reset git branch and remove all tracked files? (y/N). Press enter for NO: " -r reply
  if [[ "$reply" =~ ^[Yy]$ ]]; then
    should_reset_git=true
  fi
else
  echo "Running in non-interactive mode with default settings:"
  echo "  - Clean build: $should_clean_build"
  echo "  - Apply patches: $should_apply_patches"
  echo "  - Sign package: $should_sign_package"
  echo "  - Reset git: $should_reset_git"
  echo "  - Clean git: $should_clean_git"
fi

# Reset git branch if requested
if [ "$should_reset_git" = true ]; then
  echo "Resetting git branch and removing all tracked files..."
  cd "$_src_dir"
  git reset --hard HEAD
  cd "$_root_dir"
fi

# Clean git with exclusions for important directories
if [ "$should_clean_git" = true ]; then
  cd "$_src_dir"
  echo "Running git clean with exclusions for gn and other important tools..."

  # let's clean only in chrome
  git clean -fdx chrome/ \
    --exclude="third_party/" \
    --exclude="build_tools/" \
    --exclude="uc_staging/" \
    --exclude="buildtools/" \
    --exclude="tools/" \
    --exclude="build/"
  cd "$_root_dir"
fi

# Fetch tags and switch to Chromium version tag
cd "$_src_dir"
echo "Fetching tags and switching to Chromium version $chromium_version..."
git fetch --tags
git checkout tags/$chromium_version

echo "Running gclient sync with minimal history..."
# Use --no-history to skip git history and --shallow for minimal checkout
# These reduce checkout size and time significantly
gclient sync -D --no-history --shallow
cd "$_root_dir"

# Clean up previous build artifacts
if [ "$should_clean_build" = true ]; then
  echo "Cleaning up previous build artifacts..."
  rm -rf "$_src_dir/out/$_out_dir" || true # Remove previous output directory
fi

# Create output directory
mkdir -p "$_src_dir/out/$_out_dir"

# Apply patches
if [ "$should_apply_patches" = true ]; then
  echo "Applying patches..."
  python3 "$_root_dir/scripts/patches.py" apply "$_src_dir" "$_root_dir/patches"
fi

# Set build flags based on build type
if [ "$release" = true ]; then
  echo "Using release build configuration..."
  cat "$_root_dir/scripts/flags.macos.release.gn" >"$_src_dir/out/$_out_dir/args.gn"
else
  echo "Using debug build configuration..."
  cat "$_root_dir/scripts/flags.macos.debug.gn" >"$_src_dir/out/$_out_dir/args.gn"
fi

# Set target_cpu to the corresponding architecture
if [[ $_arch == "arm64" ]]; then
  echo 'target_cpu = "arm64"' >>"$_src_dir/out/$_out_dir/args.gn" # For ARM64/Apple Silicon
else
  echo 'target_cpu = "x64"' >>"$_src_dir/out/$_out_dir/args.gn" # For Intel x64
fi

# Copy over AI side panel resources
_ai_side_panel_dir="$_src_dir/chrome/browser/resources/ai_side_panel"

echo "Creating directory:"
echo "  $_ai_side_panel_dir"

mkdir -p "$_ai_side_panel_dir"

echo "Copying content from felafax-chromium:"
echo "  from: $_root_dir/files/ai_side_panel"
echo "    to: $_ai_side_panel_dir"

cp -r $_root_dir/files/ai_side_panel/* "$_ai_side_panel_dir"

# Copy icons from resources/output to the Chromium theme directory
_chromium_theme_dir="$_src_dir/chrome/app/theme/chromium"
copy_icons "$_root_dir/resources/gen" "$_chromium_theme_dir"

# Change to source directory for building
cd "$_src_dir"

# Generate ninja build files
if [ "$should_clean_build" = true ]; then
  echo "Generating ninja build files..."
  gn gen out/$_out_dir --fail-on-unused-args
fi

# autoninja is a wrapper around ninja that automatically sets optimal parameters
autoninja -C out/$_out_dir chrome chromedriver

# Sign and package the application
if [ "$should_sign_package" = true ]; then
  echo "Signing and packaging the application..."
  $_root_dir/sign_and_package_app.sh
fi
