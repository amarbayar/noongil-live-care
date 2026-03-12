#!/bin/bash
# Noongil build & install script
# Usage:
#   ./build.sh              # build only (no signing)
#   ./build.sh sign         # build with signing
#   ./build.sh install      # build, sign, and install to device
#   ./build.sh run          # build, sign, install, and launch on device
#   ./build.sh test         # run unit tests (Mac Catalyst)

set -eo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$PROJECT_DIR/Noongil.xcodeproj"
TARGET="Noongil"
SDK="iphoneos"
ARCH="arm64"
CONFIG="Release"
TEAM="${DEVELOPMENT_TEAM:-}"
BUILD_DIR="$PROJECT_DIR/build"
BUILD_LOG="$BUILD_DIR/build.log"
APP_PATH="$BUILD_DIR/$CONFIG-iphoneos/Noongil.app"
BUNDLE_ID="dev.example.noongil"
DEVICE_ID="${DEVICE_ID:-}"

XCODEBUILD_OVERRIDES=()
if [ -n "${GEMINI_API_KEY:-}" ]; then
    XCODEBUILD_OVERRIDES+=("GEMINI_API_KEY=$GEMINI_API_KEY")
fi
if [ -n "${BACKEND_BASE_URL:-}" ]; then
    XCODEBUILD_OVERRIDES+=("BACKEND_BASE_URL=$BACKEND_BASE_URL")
fi
if [ -n "${PUBLIC_DASHBOARD_URL:-}" ]; then
    XCODEBUILD_OVERRIDES+=("PUBLIC_DASHBOARD_URL=$PUBLIC_DASHBOARD_URL")
fi
if [ -n "${PRODUCT_BUNDLE_IDENTIFIER:-}" ]; then
    BUNDLE_ID="$PRODUCT_BUNDLE_IDENTIFIER"
    XCODEBUILD_OVERRIDES+=("PRODUCT_BUNDLE_IDENTIFIER=$PRODUCT_BUNDLE_IDENTIFIER")
fi

# Get device ID (first available iOS device)
get_device_id() {
    if [ -n "$DEVICE_ID" ]; then
        echo "$DEVICE_ID"
        return 0
    fi
    xcrun devicectl list devices 2>&1 | awk '$4 == "available" || $4 == "connected" { print $3; exit }'
}

# Run xcodebuild and fail loudly on error
run_xcodebuild() {
    local label="$1"
    shift
    echo "==> $label..."
    mkdir -p "$BUILD_DIR"

    # Run build, tee to log, and preserve exit code
    set +e
    xcodebuild "$@" 2>&1 | tee "$BUILD_LOG" | grep -E "error:|warning:|BUILD|Linking|Signing|CompileSwift" | tail -20
    local exit_code=${PIPESTATUS[0]}
    set -e

    if [ $exit_code -ne 0 ]; then
        echo ""
        echo "ERROR: $label failed (exit code $exit_code)."
        echo "       Full log: $BUILD_LOG"
        echo ""
        echo "Last errors:"
        grep -E "error:" "$BUILD_LOG" | tail -10
        exit $exit_code
    fi
}

has_real_firebase_config() {
    local plist="$PROJECT_DIR/GoogleService-Info.plist"
    [ -f "$plist" ] && ! grep -q "REPLACE_ME" "$plist"
}

require_real_firebase_config() {
    if has_real_firebase_config; then
        return 0
    fi

    echo "ERROR: ios/GoogleService-Info.plist is missing or still contains placeholder values."
    echo "       Copy in a real Firebase config before running a signed device build."
    exit 1
}

require_live_test_prereqs() {
    if [ -z "${GEMINI_API_KEY:-}" ]; then
        echo "ERROR: GEMINI_API_KEY is required for ./build.sh test-live."
        echo "       Export GEMINI_API_KEY or prefix the command with it."
        exit 1
    fi
}

require_signing_prereqs() {
    if [ -z "$TEAM" ]; then
        echo "ERROR: DEVELOPMENT_TEAM is required for signed device builds."
        echo "       Example: DEVELOPMENT_TEAM=YOURTEAMID PRODUCT_BUNDLE_IDENTIFIER=ai.noongil.app ./build.sh sign"
        exit 1
    fi

    if [ "$BUNDLE_ID" = "dev.example.noongil" ]; then
        echo "ERROR: PRODUCT_BUNDLE_IDENTIFIER is still the public placeholder ($BUNDLE_ID)."
        echo "       Set a real bundle identifier you can sign for before using sign/install/run."
        exit 1
    fi

    require_real_firebase_config

    local identities_output
    identities_output=$(security find-identity -v -p codesigning 2>/dev/null || true)
    if ! echo "$identities_output" | grep -Eq '[1-9][0-9]* valid identities found'; then
        echo "WARNING: security find-identity did not report a valid signing identity."
        echo "         Xcode may still be able to sign with automatic provisioning."
        echo "         security find-identity summary: $(echo "$identities_output" | tail -1)"
    fi
}

print_doctor_report() {
    echo "==> Noongil iOS doctor"
    echo "Project: $PROJECT_DIR"
    echo "Bundle ID: $BUNDLE_ID"
    echo "Device ID override: ${DEVICE_ID:-<auto-discover>}"
    echo "Development team: ${TEAM:-<unset>}"
    echo "GEMINI_API_KEY: $([ -n "${GEMINI_API_KEY:-}" ] && echo set || echo missing)"
    echo "BACKEND_BASE_URL: ${BACKEND_BASE_URL:-<unset>}"
    echo "PUBLIC_DASHBOARD_URL: ${PUBLIC_DASHBOARD_URL:-<unset>}"

    if has_real_firebase_config; then
        echo "Firebase plist: present"
    else
        echo "Firebase plist: missing or placeholder"
    fi

    local identities_output
    identities_output=$(security find-identity -v -p codesigning 2>/dev/null || true)
    if echo "$identities_output" | grep -Eq '[1-9][0-9]* valid identities found'; then
        echo "Code-signing identities: available"
    else
        echo "Code-signing identities: none"
        echo "Identity summary: $(echo "$identities_output" | tail -1)"
    fi
}

MODE="${1:-build}"

case "$MODE" in
    doctor)
        print_doctor_report
        exit 0
        ;;
    sign|install|run)
        require_signing_prereqs
        ;;
    test-live)
        require_live_test_prereqs
        ;;
    build|test)
        ;;
    *)
        echo "Usage: $0 [doctor|build|sign|install|run|test|test-live]"
        exit 1
        ;;
esac

# ── Step 0: Regenerate Xcode project ──
echo "==> Regenerating Xcode project..."
cd "$PROJECT_DIR"
rm -rf "$PROJECT"
xcodegen generate 2>&1

# ── Step 1: Resolve SPM packages ──
echo "==> Resolving packages..."
xcodebuild -target "$TARGET" -sdk "$SDK" -arch "$ARCH" \
    "${XCODEBUILD_OVERRIDES[@]}" \
    -resolvePackageDependencies 2>&1 | tail -3

# ── Step 2: Fix Firebase SPM build-system issues ──
#
# Firebase iOS SDK has known issues with `xcodebuild -target`:
#
# 1) nanopb BUILD file: Firebase's nanopb fork ships a Bazel "BUILD" file that
#    collides with Xcode's build/ directory on case-insensitive macOS APFS.
#    Fix: replace the file with a directory. Use -skipPackageUpdates on subsequent
#    builds to prevent SPM from restoring it.
#    See: https://github.com/firebase/firebase-ios-sdk/issues/11426
#
# 2) Cross-package module maps: With -target (not -scheme), Xcode doesn't share
#    generated module maps between SPM package checkouts. Fix: bootstrap build to
#    generate all maps, then cross-copy between all packages.
#
# NOTE: SPM checkouts live in DerivedData, NOT in SYMROOT. We must find them via
# DerivedData path, not BUILD_ROOT (which points to SYMROOT when overridden).

CHECKOUTS=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Noongil-*/SourcePackages/checkouts" -type d 2>/dev/null | head -1)
if [ -z "$CHECKOUTS" ]; then
    echo "ERROR: Could not find SPM checkouts in DerivedData. Run xcodebuild -resolvePackageDependencies first."
    exit 1
fi
echo "==> SPM checkouts: $CHECKOUTS"

# Fix nanopb BUILD file
NANOPB_BUILD="$CHECKOUTS/nanopb/build"
if [ -f "$NANOPB_BUILD" ]; then
    echo "==> Fixing nanopb build-file conflict..."
    chmod u+w "$NANOPB_BUILD"
    rm "$NANOPB_BUILD"
    mkdir -p "$NANOPB_BUILD"
fi

# Bootstrap build to generate module maps (expected to partially fail)
echo "==> Bootstrap build (generating module maps)..."
    xcodebuild \
        -target "$TARGET" \
        -sdk "$SDK" \
        -arch "$ARCH" \
        -configuration "$CONFIG" \
        CODE_SIGNING_ALLOWED=NO \
        SYMROOT="$BUILD_DIR" \
        -skipPackageUpdates \
        "${XCODEBUILD_OVERRIDES[@]}" \
        build 2>&1 | tail -3 || true

# Cross-copy all generated module maps between all packages
# Xcode 16: maps live in $CHECKOUTS/*/build/GeneratedModuleMaps-iphoneos
# Xcode 26: maps live in $BUILD_DIR/GeneratedModuleMaps-iphoneos (centralized)
echo "==> Cross-copying module maps between packages..."
ALL_MAPS_DIR="$BUILD_DIR/.all-modulemaps"
CENTRAL_MAPS="$BUILD_DIR/GeneratedModuleMaps-iphoneos"
rm -rf "$ALL_MAPS_DIR"
mkdir -p "$ALL_MAPS_DIR"

# Collect from per-package dirs (Xcode 16)
for maps_dir in "$CHECKOUTS"/*/build/GeneratedModuleMaps-iphoneos; do
    if [ -d "$maps_dir" ]; then
        cp -f "$maps_dir"/*.modulemap "$ALL_MAPS_DIR/" 2>/dev/null || true
    fi
done
# Collect from central SYMROOT dir (Xcode 26)
if [ -d "$CENTRAL_MAPS" ]; then
    cp -f "$CENTRAL_MAPS"/*.modulemap "$ALL_MAPS_DIR/" 2>/dev/null || true
fi

MAP_COUNT=$(find "$ALL_MAPS_DIR" -name "*.modulemap" 2>/dev/null | wc -l | tr -d ' ')
echo "    Collected $MAP_COUNT unique module maps"

# Distribute to per-package dirs (Xcode 16)
for maps_dir in "$CHECKOUTS"/*/build/GeneratedModuleMaps-iphoneos; do
    if [ -d "$maps_dir" ]; then
        cp -fn "$ALL_MAPS_DIR"/*.modulemap "$maps_dir/" 2>/dev/null || true
    fi
done
# Distribute to central dir (Xcode 26)
if [ -d "$CENTRAL_MAPS" ]; then
    cp -fn "$ALL_MAPS_DIR"/*.modulemap "$CENTRAL_MAPS/" 2>/dev/null || true
fi
rm -rf "$ALL_MAPS_DIR"

# ── Step 3: Real build ──
case "$MODE" in
    build)
        run_xcodebuild "Building (no signing)" \
            -target "$TARGET" \
            -sdk "$SDK" \
            -arch "$ARCH" \
            -configuration "$CONFIG" \
            CODE_SIGNING_ALLOWED=NO \
            SYMROOT="$BUILD_DIR" \
            -skipPackageUpdates \
            "${XCODEBUILD_OVERRIDES[@]}" \
            build
        echo "==> Build complete: $APP_PATH"
        ;;

    sign|install|run)
        run_xcodebuild "Building with signing (team: $TEAM)" \
            -target "$TARGET" \
            -sdk "$SDK" \
            -arch "$ARCH" \
            -configuration "$CONFIG" \
            -allowProvisioningUpdates \
            DEVELOPMENT_TEAM="$TEAM" \
            CODE_SIGN_STYLE=Automatic \
            SYMROOT="$BUILD_DIR" \
            -skipPackageUpdates \
            "${XCODEBUILD_OVERRIDES[@]}" \
            build

        # Verify the binary is actually signed
        if ! codesign -v "$APP_PATH" 2>/dev/null; then
            echo "ERROR: Build produced unsigned binary. Signing failed."
            exit 1
        fi
        echo "==> Signed build verified: $APP_PATH"

        if [ "$MODE" = "sign" ]; then
            exit 0
        fi

        # Install to device
        DEVICE_ID=$(get_device_id)
        if [ -z "$DEVICE_ID" ]; then
            echo "ERROR: No device found. Connect an iOS device and try again."
            exit 1
        fi
        echo "==> Installing to device $DEVICE_ID..."
        xcrun devicectl device install app \
            --device "$DEVICE_ID" \
            "$APP_PATH" 2>&1

        if [ "$MODE" = "run" ]; then
            echo "==> Launching on device..."
            xcrun devicectl device process launch \
                --device "$DEVICE_ID" \
                --terminate-existing \
                "$BUNDLE_ID" 2>&1
        fi

        echo "==> Done!"
        ;;

    test)
        echo "==> Running unit tests (Mac Catalyst)..."
        cd "$PROJECT_DIR"
        xcodebuild test \
            -scheme NoongilTests \
            -destination 'platform=macOS,variant=Mac Catalyst' \
            -configuration "$CONFIG" \
            -skipPackageUpdates \
            -skip-testing:NoongilTests/GeminiLiveIntegrationTests \
            SYMROOT="$BUILD_DIR" \
            MACOSX_DEPLOYMENT_TARGET=15.2 \
            IPHONEOS_DEPLOYMENT_TARGET=16.0 \
            CODE_SIGN_IDENTITY="-" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO \
            "${XCODEBUILD_OVERRIDES[@]}" \
            2>&1 | tee "$BUILD_DIR/test.log" | grep -E "(Test Suite|Test Case|Executed|FAILED|PASSED|error:)" | tail -40
        echo "==> Tests complete."
        ;;

    test-live)
        echo "==> Running Gemini Live integration tests (Mac Catalyst)..."
        echo "==> These tests connect to the real Gemini API and take 1-3 minutes."
        cd "$PROJECT_DIR"
        xcodebuild test \
            -scheme NoongilTests \
            -destination 'platform=macOS,variant=Mac Catalyst' \
            -configuration "$CONFIG" \
            -skipPackageUpdates \
            -only-testing:NoongilTests/GeminiLiveIntegrationTests \
            SYMROOT="$BUILD_DIR" \
            MACOSX_DEPLOYMENT_TARGET=15.2 \
            IPHONEOS_DEPLOYMENT_TARGET=16.0 \
            CODE_SIGN_IDENTITY="-" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO \
            "${XCODEBUILD_OVERRIDES[@]}" \
            2>&1 | tee "$BUILD_DIR/test-live.log"
        echo "==> Integration tests complete."
        ;;

    *)
        echo "Usage: $0 [doctor|build|sign|install|run|test|test-live]"
        exit 1
        ;;
esac
