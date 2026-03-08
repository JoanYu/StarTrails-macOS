#!/bin/bash
set -e

# Name of the output application
APP_NAME="StarTrails"

# Clean up old build
echo "🧹 Cleaning up previous builds..."
rm -rf "$APP_NAME.app"
swift package clean

# Build the release executable
echo "🔨 Building release executable..."
swift build -c release

# Get the path to the built executable
BIN_PATH=$(swift build -c release --show-bin-path)

# Create the .app bundle structure
echo "📦 Creating $APP_NAME.app bundle structure..."
mkdir -p "$APP_NAME.app/Contents/MacOS"
mkdir -p "$APP_NAME.app/Contents/Resources"

# Copy the executable into the bundle
echo "📄 Copying executable..."
cp "$BIN_PATH/StarTrailsApp" "$APP_NAME.app/Contents/MacOS/$APP_NAME"

# Copy any defined resources from the Swift Package Manager build folder
# Note: CoreML mlpackage bundles will be located inside the StarTrailsApp_StarTrailsApp.bundle
echo "🖼️ Copying resources..."
if [ -d "$BIN_PATH/StarTrailsApp_StarTrailsApp.bundle" ]; then
    cp -r "$BIN_PATH/StarTrailsApp_StarTrailsApp.bundle" "$APP_NAME.app/Contents/Resources/"
fi

# Create Info.plist
echo "📝 Generating Info.plist..."
cat > "$APP_NAME.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.startrails.mac</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Make the executable runnable
chmod +x "$APP_NAME.app/Contents/MacOS/$APP_NAME"

echo "✅ Build complete! You can find your macOS application at: $(pwd)/$APP_NAME.app"
echo "You can double click StarTrails.app to open it."
