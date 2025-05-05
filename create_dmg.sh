#!/bin/bash
set -e

# Get the directory of this script
_root_dir=$(dirname $(greadlink -f $0))

# Define paths
_out_dir="Default"
_nxtscape_app_path="$_root_dir/build/src/out/$_out_dir/Nxtscape.app"
_chromium_version=$(cat "$_root_dir"/scripts/chromium_version.txt)
_package_revision=$(cat "$_root_dir"/scripts/nxtscape_version.txt)
_final_dmg_path="$_root_dir/dmg/Nxtscape_${_chromium_version}-.${_package_revision}.dmg"

echo "======================================================================"
echo "Creating DMG for Nxtscape..."
echo "======================================================================"

# Make sure the dmg directory exists
mkdir -p "$_root_dir/dmg"

# Remove old DMG if it exists
if [ -f "$_final_dmg_path" ]; then
    echo "Removing existing DMG..."
    rm -f "$_final_dmg_path"
fi

# Package into DMG
echo "Packaging application into DMG..."
if ! $_root_dir/build/src/chrome/installer/mac/pkg-dmg \
  --sourcefile --source "$_nxtscape_app_path" \
  --target "$_final_dmg_path" \
  --volname "Nxtscape" \
  --symlink /Applications:/Applications \
  --format UDBZ --verbosity 2; then
    echo "ERROR: Failed to create DMG package!"
    exit 1
fi

echo "======================================================================"
echo "Process completed successfully!"
echo "DMG created at: $_final_dmg_path"
echo "======================================================================" 