#!/bin/bash
# Script to open the Astro Viewing Conditions app in Xcode with iOS simulator support
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
project="$root/apps/ios/AstroViewingConditions.xcodeproj"

if [[ ! -d "$project" ]]; then
  echo "error: Xcode project not found at $project" >&2
  echo "Generate it with: (cd \"$root/apps/ios\" && xcodegen generate)" >&2
  exit 1
fi

echo "Opening Astro Viewing Conditions in Xcode..."
echo ""
echo "IMPORTANT: After Xcode opens:"
echo "1. Wait for package resolution to complete"
echo "2. Look at the top toolbar - you should see 'My Mac' or 'AstroViewingConditions'"
echo "3. Click that dropdown and select an iOS Simulator (e.g., 'iPhone 17 Pro')"
echo "4. If no simulators appear, click 'Manage Destinations...' and add iOS simulators"
echo ""

# Open the .xcodeproj, not the repository directory (which would import
# Python, contracts, and other non-Apple files into the project).
open -a Xcode "$project"
