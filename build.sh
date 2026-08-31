#!/usr/bin/env bash
#
# One command per shippable artifact.
#
# This exists because the three products do NOT share a command shape, and
# guessing wrong fails in confusing ways:
#
#   - Android ships TWO products from one codebase (phone + Android TV), so
#     every Android build needs --flavor, its own Dart entrypoint, and for TV
#     the IS_TV compile-time define. Omitting any of them silently builds the
#     wrong app.
#   - iOS ships ONE product, so it has no Xcode flavor schemes at all.
#     Passing --flavor there fails with "You must specify a --flavor option
#     to select one of the available schemes" — the flavor is an Android
#     concept, not a missing iOS config.
#
# See android/app/build.gradle.kts for the flavor definitions and
# lib/core/build_flavor.dart for the kIsTv compile-time flag.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: ./build.sh <target> [--debug]

Targets:
  phone-apk      Android phone  -> APK   (testing/sideload)
  phone-aab      Android phone  -> AAB   (Play Console upload)
  tv-apk         Android TV     -> APK   (testing/sideload on a TV box)
  tv-aab         Android TV     -> AAB   (Play Console "Android TV" release)
  ios            iOS            -> .app  (no codesign, for CI/local checks)
  ipa            iOS            -> .ipa  (signed, App Store upload)
  all-aab        Both Android AABs, ready to upload

Options:
  --debug        Build debug instead of release (Android targets only)

Examples:
  ./build.sh tv-apk --debug     # quick TV build to sideload while iterating
  ./build.sh all-aab            # both Play Console uploads
  ./build.sh ipa                # App Store build
EOF
}

TARGET="${1:-}"
MODE="--release"
if [[ "${2:-}" == "--debug" ]]; then
    MODE="--debug"
fi

# Android TV needs all three of these together, every time. IS_TV drives
# kIsTv, which is a bool.fromEnvironment const — so it also dead-code
# strips the TV UI out of the phone binary and vice versa.
TV_ARGS=(--flavor tv -t lib/main_tv.dart --dart-define=IS_TV=true)
PHONE_ARGS=(--flavor phone -t lib/main.dart)

case "$TARGET" in
    phone-apk) flutter build apk       "${PHONE_ARGS[@]}" "$MODE" ;;
    phone-aab) flutter build appbundle "${PHONE_ARGS[@]}" "$MODE" ;;
    tv-apk)    flutter build apk       "${TV_ARGS[@]}"    "$MODE" ;;
    tv-aab)    flutter build appbundle "${TV_ARGS[@]}"    "$MODE" ;;

    # No --flavor: iOS has a single product and a single Runner scheme.
    ios)       flutter build ios --release --no-codesign ;;
    ipa)       flutter build ipa --release ;;

    all-aab)
        flutter build appbundle "${PHONE_ARGS[@]}" --release
        flutter build appbundle "${TV_ARGS[@]}"    --release
        echo ""
        echo "Ready to upload:"
        echo "  phone : build/app/outputs/bundle/phoneRelease/app-phone-release.aab"
        echo "  tv    : build/app/outputs/bundle/tvRelease/app-tv-release.aab"
        ;;

    ""|-h|--help|help) usage ;;
    *) echo "Unknown target: $TARGET" >&2; echo "" >&2; usage >&2; exit 1 ;;
esac
