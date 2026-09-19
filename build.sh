#!/bin/bash

root="$(cd "$(dirname "$0")" && pwd)"

xcodebuild -project "$root/apps/ios/AstroViewingConditions.xcodeproj" \
  -scheme AstroViewingConditions \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build
