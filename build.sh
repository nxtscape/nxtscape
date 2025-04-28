#!/usr/bin/env bash

# Exit immediately if a command fails (e), treat unset variables as errors (u),
# and print commands before execution (x)
set -eux

# Build script for local macOS environment

# Some path variables
_root_dir=$(dirname $(greadlink -f $0))  # Gets the absolute path of the script directory
_src_dir="$_root_dir/build/src/"  # Chromium source code directory
_out_dir="Release"


# Parse command line options
clone=true  # Default is to clone the source repository
while getopts 'd' OPTION; do
  case "$OPTION" in
  d)
    clone=false  # -d option disables cloning, uses downloads instead
    ;;
  esac
done

shift "$(($OPTIND - 1))"  # Shift positional parameters to access non-option arguments

_arch=${1:-arm64}  # Set build architecture, default to arm64 if not specified


# Clean up previous build artifacts
# rm -rf "$_src_dir/out" || true  # Remove previous output directory

# Create output directory
mkdir -p "$_src_dir/out/$_out_dir"

# Apply patches
# python3 "$_root_dir/scripts/patches.py" apply "$_src_dir" "$_root_dir/patches"  

# Set build flags by combining flag files
cat "$_root_dir/scripts/flags.macos.gn" >"$_src_dir/out/$_out_dir/args.gn"


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
# gn gen out/$_out_dir --fail-on-unused-args

# autoninja is a wrapper around ninja that automatically sets optimal parameters
autoninja -C out/$_out_dir chrome chromedriver

# Sign and package the application
# "$_root_dir/sign_and_package_app.sh"