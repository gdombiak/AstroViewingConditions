#!/bin/bash

xcodebuild -project AstroViewingConditions.xcodeproj \
  -scheme AstroViewingConditions \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build
