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
_root_dir=$(dirname $(greadlink -f $0))  # Gets the absolute path of the script directory
_src_dir="$_root_dir/build/src/"  # Chromium source code directory
_out_dir="Default"

# Parse command line options
release=false  # Default is debug build
non_interactive=false  # Default is interactive mode
while getopts 'rn' OPTION; do
  case "$OPTION" in
  r)
    release=true  # -r option enables release build
    ;;
  n)
    non_interactive=true  # -n option enables non-interactive mode
    ;;
  esac
done

shift "$(($OPTIND - 1))"  # Shift positional parameters to access non-option arguments

_arch=${1:-arm64}  # Set build architecture, default to arm64 if not specified

# Variables for build steps - will be prompted
should_apply_patches=true
should_sign_package=true
should_clean_build=true

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
else
  echo "Running in non-interactive mode with default settings:"
  echo "  - Clean build: $should_clean_build"
  echo "  - Apply patches: $should_apply_patches"
  echo "  - Sign package: $should_sign_package"
fi

# Clean up previous build artifacts
if [ "$should_clean_build" = true ]; then
  echo "Cleaning up previous build artifacts..."
  rm -rf "$_src_dir/out/$_out_dir" || true  # Remove previous output directory
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
  echo 'target_cpu = "arm64"' >>"$_src_dir/out/$_out_dir/args.gn"  # For ARM64/Apple Silicon
else
  echo 'target_cpu = "x64"' >>"$_src_dir/out/$_out_dir/args.gn"  # For Intel x64
fi

# Copy over AI agent and side panel resources
_ai_agent_side_panel_dir="$_src_dir/chrome/browser/resources/ai_agent_side_panel"
_ai_side_panel_dir="$_src_dir/chrome/browser/resources/ai_side_panel"

echo "Creating directories:"
echo "  $_ai_agent_side_panel_dir"
echo "  $_ai_side_panel_dir"

mkdir -p "$_ai_agent_side_panel_dir"
mkdir -p "$_ai_side_panel_dir"

echo "Copying content from felafax-chromium:"
echo "  from: $_root_dir/files/ai_agent_side_panel"
echo "    to: $_ai_agent_side_panel_dir"
echo "  from: $_root_dir/files/ai_side_panel"
echo "    to: $_ai_side_panel_dir"

cp -r $_root_dir/files/ai_agent_side_panel/* "$_ai_agent_side_panel_dir"
cp -r $_root_dir/files/ai_side_panel/* "$_ai_side_panel_dir"

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