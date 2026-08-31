#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
# Build only. Never install over the existing Python app in /Applications.
xcodebuild -project MacbookAccordion.xcodeproj \
  -scheme MacbookAccordion -configuration Release \
  -derivedDataPath build/native \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
app_path="$PWD/build/native/Build/Products/Release/MacbookAccordion Native.app"
codesign --verify --deep --strict "$app_path"
printf '\nNative app: %s\n' "$app_path"
