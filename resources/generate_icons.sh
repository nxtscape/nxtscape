#!/usr/bin/env bash

# ==========================================================================
# NXTscape Browser Icon Generator Script
# ==========================================================================
# Usage: ./generate_icons.sh <image_path> <output_dir>
#
# This script takes an SVG or PNG icon and generates all required icons for
# the Chrome/Chromium browser project in various formats and sizes.
#
# Dependencies:
#   - ImageMagick (convert, identify)
#   - librsvg (rsvg-convert) - only needed for SVG input
#   - icoutils (for Windows icons)
#
# Example:
#   ./generate_icons.sh product_logo.svg ./output
#   ./generate_icons.sh product_logo.png ./output
# ==========================================================================

set -eu

# Check dependencies
command -v identify >/dev/null 2>&1 || { echo "ImageMagick (identify) is required but not installed. Aborting."; exit 1; }

# Determine which ImageMagick command to use (magick for v7, convert for v6)
if command -v magick >/dev/null 2>&1; then
    CONVERT_CMD="magick"
    echo "Using ImageMagick v7 command: magick"
else
    command -v convert >/dev/null 2>&1 || { echo "ImageMagick (convert) is required but not installed. Aborting."; exit 1; }
    CONVERT_CMD="convert"
    echo "Using ImageMagick v6 command: convert"
fi

# macOS-specific tools
if [[ "$(uname)" == "Darwin" ]]; then
    # Check if we're on macOS and can use the native iconutil
    USE_ICONUTIL=true
    command -v iconutil >/dev/null 2>&1 || USE_ICONUTIL=false
    echo "Using macOS iconutil for .icns creation: $USE_ICONUTIL"
else
    # Check for png2icns on other platforms
    USE_ICONUTIL=false
    command -v png2icns >/dev/null 2>&1 || { echo "png2icns is required for non-macOS platforms but not installed. Aborting."; exit 1; }
fi

command -v icotool >/dev/null 2>&1 || { echo "icoutils is required but not installed. Aborting."; exit 1; }

# Check arguments
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <image_path> <output_dir>"
    exit 1
fi

IMAGE_PATH="$1"
OUTPUT_DIR="$2"

# Verify image file exists
if [ ! -f "$IMAGE_PATH" ]; then
    echo "Error: Image file '$IMAGE_PATH' not found."
    exit 1
fi

# Detect file type
FILE_TYPE=$(identify -format "%m" "$IMAGE_PATH")
if [[ "$FILE_TYPE" == "SVG" ]]; then
    echo "Detected SVG input file."
    IS_SVG=true
    # Check for rsvg-convert dependency
    command -v rsvg-convert >/dev/null 2>&1 || { echo "librsvg (rsvg-convert) is required for SVG files but not installed. Aborting."; exit 1; }
elif [[ "$FILE_TYPE" == "PNG" ]]; then
    echo "Detected PNG input file."
    IS_SVG=false
else
    echo "Error: Input file must be SVG or PNG format. Detected: $FILE_TYPE"
    exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Create required subdirectories
mkdir -p "$OUTPUT_DIR/chromeos"
mkdir -p "$OUTPUT_DIR/linux"
mkdir -p "$OUTPUT_DIR/mac"
mkdir -p "$OUTPUT_DIR/win"
mkdir -p "$OUTPUT_DIR/win/tiles"

# Function to ensure an image is square by adding transparent padding if needed
ensure_square() {
    local input="$1"
    local output="$2"
    
    # Get dimensions
    local width=$(identify -format "%w" "$input")
    local height=$(identify -format "%h" "$input")
    
    if [ "$width" -ne "$height" ]; then
        echo "Making image square: $input (${width}x${height})"
        local size=$(( width > height ? width : height ))
        $CONVERT_CMD "$input" -background transparent -gravity center -extent "${size}x${size}" "$output"
    else
        # If already square, just copy
        cp "$input" "$output"
    fi
}

# Function to generate PNG from source image at specified size
generate_png() {
    local size="$1"
    local output_path="$2"
    local background="$3"  # Optional background parameter
    
    mkdir -p "$(dirname "$output_path")"
    
    if [ "$IS_SVG" = true ]; then
        # For SVG input
        if [ -n "$background" ]; then
            # With background color
            rsvg-convert -w "$size" -h "$size" "$IMAGE_PATH" -o temp.png
            $CONVERT_CMD temp.png -background "$background" -flatten "$output_path"
            rm temp.png
        else
            # Standard transparent background
            rsvg-convert -w "$size" -h "$size" "$IMAGE_PATH" -o "$output_path"
        fi
    else
        # For PNG input
        if [ -n "$background" ]; then
            # With background color
            $CONVERT_CMD "$IMAGE_PATH" -resize "${size}x${size}" -background "$background" -flatten "$output_path"
        else
            # Standard transparent background
            $CONVERT_CMD "$IMAGE_PATH" -resize "${size}x${size}" "$output_path"
        fi
    fi
    
    # Ensure the output is square (important for icons)
    if [ -f "$output_path" ]; then
        ensure_square "$output_path" "$output_path.tmp"
        mv "$output_path.tmp" "$output_path"
    fi
    
    echo "Generated: $output_path"
}

# Function to generate XPM from PNG
generate_xpm() {
    local png_path="$1"
    local xpm_path="$2"
    
    $CONVERT_CMD "$png_path" "$xpm_path"
    echo "Generated: $xpm_path"
}

# Function to create macOS iconset directory with all required sizes
create_mac_iconset() {
    local output_dir="$1"
    local iconset_dir="$2"
    local source_dir="$3"
    
    mkdir -p "$iconset_dir"
    
    # Copy PNG files to iconset directory with required names
    cp "$source_dir/icon_16x16.png" "$iconset_dir/icon_16x16.png"
    cp "$source_dir/icon_16x16@2x.png" "$iconset_dir/icon_32x32@2x.png"
    cp "$source_dir/icon_32x32.png" "$iconset_dir/icon_32x32.png"
    cp "$source_dir/icon_32x32@2x.png" "$iconset_dir/icon_64x64@2x.png"
    cp "$source_dir/icon_128x128.png" "$iconset_dir/icon_128x128.png"
    cp "$source_dir/icon_128x128@2x.png" "$iconset_dir/icon_256x256@2x.png"
    cp "$source_dir/icon_256x256.png" "$iconset_dir/icon_256x256.png"
    cp "$source_dir/icon_256x256@2x.png" "$iconset_dir/icon_512x512@2x.png"
    cp "$source_dir/icon_512x512.png" "$iconset_dir/icon_512x512.png"
    
    if [ "$USE_ICONUTIL" = true ]; then
        # Use macOS iconutil to create .icns file
        echo "Creating .icns file using iconutil..."
        iconutil -c icns -o "$output_dir" "$iconset_dir"
    else
        # Use png2icns if not on macOS
        echo "Creating .icns file using png2icns..."
        png2icns "$output_dir" "$source_dir"/*.png || echo "Warning: png2icns may have encountered issues generating icns file"
    fi
    
    echo "Generated: $output_dir"
}

# ==== Generate standard PNGs ====
echo "Generating standard PNG files..."
PNG_SIZES=(16 22 24 32 48 64 128 192 256)

for size in "${PNG_SIZES[@]}"; do
    generate_png "$size" "$OUTPUT_DIR/product_logo_${size}.png" ""
done

# Generate special mono version (22px)
$CONVERT_CMD "$OUTPUT_DIR/product_logo_22.png" -colorspace gray "$OUTPUT_DIR/product_logo_22_mono.png"
echo "Generated: $OUTPUT_DIR/product_logo_22_mono.png"

# ==== Generate ChromeOS icons ====
echo "Generating ChromeOS icons..."
generate_png 32 "$OUTPUT_DIR/chromeos/chrome_app_icon_32.png" ""
generate_png 192 "$OUTPUT_DIR/chromeos/chrome_app_icon_192.png" ""
generate_png 256 "$OUTPUT_DIR/chromeos/crosh_app_icon_256.png" ""
generate_png 16 "$OUTPUT_DIR/chromeos/webstore_app_icon_16.png" ""
generate_png 128 "$OUTPUT_DIR/chromeos/webstore_app_icon_128.png" ""

# ==== Generate Linux icons ====
echo "Generating Linux icons..."
generate_png 24 "$OUTPUT_DIR/linux/product_logo_24.png" ""
generate_png 48 "$OUTPUT_DIR/linux/product_logo_48.png" ""
generate_png 64 "$OUTPUT_DIR/linux/product_logo_64.png" ""
generate_png 128 "$OUTPUT_DIR/linux/product_logo_128.png" ""
generate_png 256 "$OUTPUT_DIR/linux/product_logo_256.png" ""

# Generate XPM icons (for Linux)
generate_xpm "$OUTPUT_DIR/product_logo_32.png" "$OUTPUT_DIR/linux/product_logo_32.xpm"

# ==== Generate Windows icons ====
echo "Generating Windows icons..."

# Generate Windows tiles
generate_png 150 "$OUTPUT_DIR/win/tiles/Logo.png" "#1A73E8"
generate_png 70 "$OUTPUT_DIR/win/tiles/SmallLogo.png" "#1A73E8"

# Create temporary directory for ICO generation
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Generate Windows ICO files (using multiple PNG sizes for each ICO)
echo "Creating Windows ICO files..."

# Generate chromium.ico (main application icon)
for size in 16 32 48 256; do
    cp "$OUTPUT_DIR/product_logo_${size}.png" "$TEMP_DIR/${size}.png"
done
icotool -c "$TEMP_DIR/16.png" "$TEMP_DIR/32.png" "$TEMP_DIR/48.png" "$TEMP_DIR/256.png" -o "$OUTPUT_DIR/win/chromium.ico"
echo "Generated: $OUTPUT_DIR/win/chromium.ico"

# Generate incognito.ico
# For demo purposes, we'll use a darkened version of the original icon
for size in 16 32 48 256; do
    $CONVERT_CMD "$OUTPUT_DIR/product_logo_${size}.png" -modulate 80,100,100 "$TEMP_DIR/${size}_dark.png"
done
icotool -c "$TEMP_DIR/16_dark.png" "$TEMP_DIR/32_dark.png" "$TEMP_DIR/48_dark.png" "$TEMP_DIR/256_dark.png" -o "$OUTPUT_DIR/win/incognito.ico"
echo "Generated: $OUTPUT_DIR/win/incognito.ico"

# Generate app_list.ico 
for size in 16 32 48; do
    cp "$OUTPUT_DIR/product_logo_${size}.png" "$TEMP_DIR/${size}_app.png"
done
icotool -c "$TEMP_DIR/16_app.png" "$TEMP_DIR/32_app.png" "$TEMP_DIR/48_app.png" -o "$OUTPUT_DIR/win/app_list.ico"
echo "Generated: $OUTPUT_DIR/win/app_list.ico"

# Generate chromium_doc.ico
for size in 16 32 48 256; do
    $CONVERT_CMD "$OUTPUT_DIR/product_logo_${size}.png" -background white -alpha remove -alpha off "$TEMP_DIR/${size}_doc.png"
done
icotool -c "$TEMP_DIR/16_doc.png" "$TEMP_DIR/32_doc.png" "$TEMP_DIR/48_doc.png" "$TEMP_DIR/256_doc.png" -o "$OUTPUT_DIR/win/chromium_doc.ico"
echo "Generated: $OUTPUT_DIR/win/chromium_doc.ico"

# Generate chromium_pdf.ico
for size in 16 32 48 256; do
    $CONVERT_CMD "$OUTPUT_DIR/product_logo_${size}.png" -background white -alpha remove -alpha off "$TEMP_DIR/${size}_pdf.png"
done
icotool -c "$TEMP_DIR/16_pdf.png" "$TEMP_DIR/32_pdf.png" "$TEMP_DIR/48_pdf.png" "$TEMP_DIR/256_pdf.png" -o "$OUTPUT_DIR/win/chromium_pdf.ico"
echo "Generated: $OUTPUT_DIR/win/chromium_pdf.ico"

# Create Windows README file
cat > "$OUTPUT_DIR/win/README" << 'EOL'
The icons in this directory are used by the Windows version of the browser.
- chromium.ico: Main application icon
- incognito.ico: Icon for incognito mode
- app_list.ico: Icon for app list
- chromium_doc.ico: Icon for HTML documents
- chromium_pdf.ico: Icon for PDF documents
- tiles/: Contains icons used for Windows tiles
EOL
echo "Generated: $OUTPUT_DIR/win/README"

# ==== Generate macOS icons ====
echo "Generating macOS icons..."
PNG_DIR=$(mktemp -d)
trap 'rm -rf "$PNG_DIR"' EXIT

# For app.icns and document.icns, we need various sizes
ICNS_SIZES=(16 32 64 128 256 512 1024)
for size in "${ICNS_SIZES[@]}"; do
    generate_png "$size" "$PNG_DIR/icon_${size}x${size}.png" ""
    # Also generate @2x versions for Retina displays
    if [ "$size" -lt 512 ]; then
        generate_png "$((size*2))" "$PNG_DIR/icon_${size}x${size}@2x.png" ""
    fi
done

# Create app.icns
APP_ICONSET=$(mktemp -d)/app.iconset
create_mac_iconset "$OUTPUT_DIR/mac/app.icns" "$APP_ICONSET" "$PNG_DIR"

# Create document.icns (similar process but with different styling for documents)
DOC_PNG_DIR=$(mktemp -d)
trap 'rm -rf "$DOC_PNG_DIR"' EXIT

for size in "${ICNS_SIZES[@]}"; do
    # Convert to a document-style icon (simplified for this script)
    $CONVERT_CMD "$PNG_DIR/icon_${size}x${size}.png" -background white -alpha remove -alpha off "$DOC_PNG_DIR/icon_${size}x${size}.png"
    if [ "$size" -lt 512 ]; then
        $CONVERT_CMD "$PNG_DIR/icon_${size}x${size}@2x.png" -background white -alpha remove -alpha off "$DOC_PNG_DIR/icon_${size}x${size}@2x.png"
    fi
done

# Create document.icns
DOC_ICONSET=$(mktemp -d)/document.iconset
create_mac_iconset "$OUTPUT_DIR/mac/document.icns" "$DOC_ICONSET" "$DOC_PNG_DIR"

# If we're on macOS and iconutil failed, use sips to at least create some .icns files
if [[ "$(uname)" == "Darwin" ]] && [ ! -f "$OUTPUT_DIR/mac/app.icns" ]; then
    echo "Attempting alternative method for .icns creation on macOS..."
    $CONVERT_CMD "$OUTPUT_DIR/product_logo_256.png" -resize 512x512 "$OUTPUT_DIR/mac/app.png"
    sips -s format icns "$OUTPUT_DIR/mac/app.png" --out "$OUTPUT_DIR/mac/app.icns" >/dev/null 2>&1 || echo "Unable to create app.icns"
    
    $CONVERT_CMD "$OUTPUT_DIR/product_logo_256.png" -background white -alpha remove -alpha off -resize 512x512 "$OUTPUT_DIR/mac/document.png"
    sips -s format icns "$OUTPUT_DIR/mac/document.png" --out "$OUTPUT_DIR/mac/document.icns" >/dev/null 2>&1 || echo "Unable to create document.icns"
    
    # Clean up temporary files
    rm -f "$OUTPUT_DIR/mac/app.png" "$OUTPUT_DIR/mac/document.png"
fi

# Copy the original image as SVG (if it's SVG) or convert to SVG (if it's PNG)
if [ "$IS_SVG" = true ]; then
    cp "$IMAGE_PATH" "$OUTPUT_DIR/product_logo.svg"
    echo "Copied: $OUTPUT_DIR/product_logo.svg"
    
    # Create animated SVG (simplified for this script - actual animation would be more complex)
    cp "$IMAGE_PATH" "$OUTPUT_DIR/product_logo_animation.svg"
    echo "Created: $OUTPUT_DIR/product_logo_animation.svg (Note: this is just a copy, real animation would need to be implemented)"
else
    # For PNG input, we don't create SVG files but instead copy the PNG
    cp "$IMAGE_PATH" "$OUTPUT_DIR/product_logo.png"
    echo "Copied: $OUTPUT_DIR/product_logo.png"
    
    # Create placeholder files
    touch "$OUTPUT_DIR/product_logo.svg"
    touch "$OUTPUT_DIR/product_logo_animation.svg"
    echo "Created placeholder SVG files (empty). For SVG files, provide an SVG source."
fi

# Create Adobe Illustrator files (placeholder)
touch "$OUTPUT_DIR/product_logo.ai"
touch "$OUTPUT_DIR/chromium.ai"
echo "Created AI file placeholders. These would need to be created manually in Adobe Illustrator."

echo "============================="
echo "Icon generation complete!"
echo "All icons have been saved to: $OUTPUT_DIR"
echo "============================="

# Add a note about potentially missing dependencies
echo "Note: If some icons weren't generated correctly, check that you have all required dependencies installed:"
echo "  - ImageMagick: for image manipulation"
if [ "$IS_SVG" = true ]; then
    echo "  - librsvg: for SVG to PNG conversion"
fi
if [ "$USE_ICONUTIL" = true ]; then
    echo "  - iconutil: for macOS icons (built into macOS)"
else
    echo "  - png2icns: for macOS icons"
fi
echo "  - icoutils: for Windows icons" 