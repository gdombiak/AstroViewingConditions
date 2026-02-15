#!/bin/bash
# Script to open the Astro Viewing Conditions app in Xcode with iOS simulator support

echo "Opening Astro Viewing Conditions in Xcode..."
echo ""
echo "IMPORTANT: After Xcode opens:"
echo "1. Wait for package resolution to complete"
echo "2. Look at the top toolbar - you should see 'My Mac' or 'AstroViewingConditions'"
echo "3. Click that dropdown and select an iOS Simulator (e.g., 'iPhone 16 Pro')"
echo "4. If no simulators appear, click 'Manage Destinations...' and add iOS simulators"
echo ""

# Open the directory in Xcode
open -a Xcode .
