#!/bin/bash
set -e  # Removed to allow script to continue on errors

# Get the directory of this script
_root_dir=$(dirname $(greadlink -f $0))

# Define paths
_out_dir="Default"
_nxtscape_app_path="$_root_dir/build/src/out/$_out_dir/Nxtscape.app"
_notarize_zip_path="$_root_dir/notarize.zip"
_chromium_version=$(cat "$_root_dir"/scripts/chromium_version.txt)
_package_revision=$(cat "$_root_dir"/scripts/nxtscape_version.txt)
_final_dmg_path="$_root_dir/dmg/Nxtscape_${_chromium_version}-.${_package_revision}_signed.dmg"

# Track errors
_error_count=0
_error_messages=""

# Function to log errors without exiting
log_error() {
    _error_count=$((_error_count + 1))
    _error_messages="${_error_messages}ERROR ${_error_count}: $1\n"
    echo "ERROR: $1"
}

# Check if environment variables are set
if [ -z "$MACOS_CERTIFICATE_NAME" ] || [ -z "$PROD_MACOS_NOTARIZATION_APPLE_ID" ] || [ -z "$PROD_MACOS_NOTARIZATION_TEAM_ID" ] || [ -z "$PROD_MACOS_NOTARIZATION_PWD" ]; then
    log_error "Required environment variables are not set. Please set MACOS_CERTIFICATE_NAME, PROD_MACOS_NOTARIZATION_APPLE_ID, PROD_MACOS_NOTARIZATION_TEAM_ID, and PROD_MACOS_NOTARIZATION_PWD"
    exit 1
fi

echo "======================================================================"
echo "Starting signing process for Nxtscape..."
echo "======================================================================"

# Fix issue where macOS requests permission for incoming network connections
echo "Clearing extended attributes..."
xattr -cs "$_nxtscape_app_path"

# Sign components individually (bottom-up approach)
echo "Signing all components..."
codesign --sign "$MACOS_CERTIFICATE_NAME" --force --timestamp --identifier org.nxtscape.crashpad_handler --options=restrict,library,runtime,kill "$_nxtscape_app_path/Contents/Frameworks/Nxtscape Framework.framework/Helpers/chrome_crashpad_handler"
codesign --sign "$MACOS_CERTIFICATE_NAME" --force --timestamp --identifier org.nxtscape.helper --options restrict,library,runtime,kill "$_nxtscape_app_path/Contents/Frameworks/Nxtscape Framework.framework/Helpers/Nxtscape Helper.app"
codesign --sign "$MACOS_CERTIFICATE_NAME" --force --timestamp --identifier org.nxtscape.helper.renderer --options restrict,kill,runtime --entitlements $_root_dir/entitlements/helper-renderer-entitlements.plist "$_nxtscape_app_path/Contents/Frameworks/Nxtscape Framework.framework/Helpers/Nxtscape Helper (Renderer).app"
codesign --sign "$MACOS_CERTIFICATE_NAME" --force --timestamp --identifier org.nxtscape.helper.gpu --options restrict,kill,runtime --entitlements $_root_dir/entitlements/helper-gpu-entitlements.plist "$_nxtscape_app_path/Contents/Frameworks/Nxtscape Framework.framework/Helpers/Nxtscape Helper (GPU).app"
codesign --sign "$MACOS_CERTIFICATE_NAME" --force --timestamp --identifier org.nxtscape.helper.plugin --options restrict,kill,runtime --entitlements $_root_dir/entitlements/helper-plugin-entitlements.plist "$_nxtscape_app_path/Contents/Frameworks/Nxtscape Framework.framework/Helpers/Nxtscape Helper (Plugin).app"
codesign --sign "$MACOS_CERTIFICATE_NAME" --force --timestamp --identifier org.nxtscape.helper.alerts --options restrict,library,runtime,kill "$_nxtscape_app_path/Contents/Frameworks/Nxtscape Framework.framework/Helpers/Nxtscape Helper (Alerts).app"
codesign --sign "$MACOS_CERTIFICATE_NAME" --force --timestamp --identifier org.nxtscape.app_mode_loader --options restrict,library,runtime,kill "$_nxtscape_app_path/Contents/Frameworks/Nxtscape Framework.framework/Helpers/app_mode_loader"
codesign --sign "$MACOS_CERTIFICATE_NAME" --force --timestamp --identifier org.nxtscape.web_app_shortcut_copier --options restrict,library,runtime,kill "$_nxtscape_app_path/Contents/Frameworks/Nxtscape Framework.framework/Helpers/web_app_shortcut_copier"
codesign --sign "$MACOS_CERTIFICATE_NAME" --force --timestamp --identifier org.nxtscape.libEGL "$_nxtscape_app_path/Contents/Frameworks/Nxtscape Framework.framework/Libraries/libEGL.dylib"
codesign --sign "$MACOS_CERTIFICATE_NAME" --force --timestamp --identifier org.nxtscape.libGLESv2 "$_nxtscape_app_path/Contents/Frameworks/Nxtscape Framework.framework/Libraries/libGLESv2.dylib"
codesign --sign "$MACOS_CERTIFICATE_NAME" --force --timestamp --identifier org.nxtscape.libvk_swiftshader "$_nxtscape_app_path/Contents/Frameworks/Nxtscape Framework.framework/Libraries/libvk_swiftshader.dylib"
codesign --sign "$MACOS_CERTIFICATE_NAME" --force --timestamp --identifier org.nxtscape.framework "$_nxtscape_app_path/Contents/Frameworks/Nxtscape Framework.framework"
codesign --sign "$MACOS_CERTIFICATE_NAME" --force --timestamp --identifier org.nxtscape.Nxtscape "$_nxtscape_app_path/Contents/MacOS/Nxtscape" # EXTRA
codesign --sign "$MACOS_CERTIFICATE_NAME" --force --timestamp --identifier org.nxtscape.Nxtscape --options restrict,library,runtime,kill --entitlements $_root_dir/entitlements/app-entitlements.plist --requirements '=designated => identifier "org.nxtscape.Nxtscape" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */' "$_nxtscape_app_path"

# --- Verify Signature ---
echo "Verifying application signature integrity..."
if ! codesign --verify --deep --strict --verbose=2 "$_nxtscape_app_path"; then
    log_error "codesign verification failed!"
    exit 1
else
    echo "Signature verification passed."
fi

# --- Prepare for Notarization ---
echo "Preparing archive for notarization..."
# Remove old zip if it exists
rm -f "$_notarize_zip_path"
# Create zip archive
ditto -c -k --keepParent "$_nxtscape_app_path" "$_notarize_zip_path"
echo "Archive created at $_notarize_zip_path"

# --- Notarize the App ---
echo "Storing notarization credentials (if not already stored)..."
# This stores the app-specific password securely in the keychain. Only needs to succeed once.
xcrun notarytool store-credentials "notarytool-profile" --apple-id "$PROD_MACOS_NOTARIZATION_APPLE_ID" --team-id "$PROD_MACOS_NOTARIZATION_TEAM_ID" --password "$PROD_MACOS_NOTARIZATION_PWD"

echo "Submitting application for notarization (will wait for completion)..."
# Submit and wait for Apple's response
if ! xcrun notarytool submit "$_notarize_zip_path" --keychain-profile "notarytool-profile" --wait; then
    log_error "Notarization submission failed. Check Apple's notarization history or logs for details."
    echo "xcrun notarytool history --keychain-profile \"notarytool-profile\""
else
    echo "Notarization submission successful."
fi

# --- Staple Notarization Ticket ---
echo "Stapling notarization ticket to application..."
if ! xcrun stapler staple "$_nxtscape_app_path"; then
    log_error "Failed to staple notarization ticket!"
else
    echo "Notarization ticket stapled successfully."
fi

# Clean up the temporary zip file
rm -f "$_notarize_zip_path"

# --- Verify Notarization and Stapling ---
echo "Verifying final notarization status and stapling..."
# Check Gatekeeper assessment (should now show Developer ID source)
if ! spctl -a -vvv "$_nxtscape_app_path"; then
    log_error "spctl Gatekeeper check failed after stapling!"
fi

# Validate the stapled ticket
if ! xcrun stapler validate "$_nxtscape_app_path"; then
    log_error "stapler validation failed after stapling!"
else
    echo "Notarization and stapling verification passed."
fi

# --- Package the App ---
echo "Packaging the notarized application into DMG..."

# Remove old DMG if it exists
rm -f "$_final_dmg_path"

# Package into DMG using the correct, stapled app bundle
if ! $_root_dir/build/src/chrome/installer/mac/pkg-dmg \
  --sourcefile --source "$_nxtscape_app_path" \
  --target "$_final_dmg_path" \
  --volname "Nxtscape" \
  --symlink /Applications:/Applications \
  --format UDBZ --verbosity 2; then
    log_error "Failed to create DMG package!"
fi

# --- Sign the DMG ---
if ! codesign --sign "$MACOS_CERTIFICATE_NAME" --force --timestamp "$_final_dmg_path"; then
    log_error "Failed to sign DMG package!"
fi

# --- Verify DMG Signature ---
echo "Verifying DMG signature..."
if ! codesign -vvv "$_final_dmg_path"; then
    log_error "DMG signing verification failed!"
else
    echo "DMG signing verification successful!"
fi

# --- Notarize the DMG ---
echo "Notarizing DMG package..."
if ! xcrun notarytool submit "$_final_dmg_path" --keychain-profile "notarytool-profile" --wait; then
    log_error "DMG notarization failed!"
else
    echo "DMG notarization successful!"
fi

# --- Staple the DMG ---
echo "Stapling notarization ticket to DMG..."
if ! xcrun stapler staple "$_final_dmg_path"; then
    log_error "Failed to staple notarization ticket to DMG!"
else
    echo "DMG notarization ticket stapled successfully."
fi

# --- Verify DMG Stapling ---
echo "Verifying DMG stapling..."
if ! xcrun stapler validate "$_final_dmg_path"; then
    log_error "DMG stapling verification failed!"
else
    echo "DMG stapling verification successful!"
fi

# --- Final Security Assessment ---
echo "Performing final security assessment verification..."
if ! spctl -a -vvv -t open --context context:primary-signature "$_final_dmg_path"; then
    log_error "Final security assessment failed!"
else
    echo "Final security assessment passed!"
fi

# --- Summary Report ---
echo "======================================================================"
if [ $_error_count -gt 0 ]; then
    echo "Process completed with $_error_count errors:"
    echo -e "$_error_messages"
    echo "Review the errors above and address them before distribution."
    echo "Final DMG created at: $_final_dmg_path (may have issues)"
else
    echo "Process completed successfully!"
    echo "Final DMG created at: $_final_dmg_path"
    echo "The application is properly signed, notarized, and packaged."
fi
echo "======================================================================"
