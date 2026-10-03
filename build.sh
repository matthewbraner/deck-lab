#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP="../Deck Lab.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -whole-module-optimization -parse-as-library -target arm64-apple-macosx14.0 -O Sources/Core.swift Sources/YGO.swift Sources/Collection.swift Sources/CollectionView.swift Sources/Artwork.swift Sources/AdvancedFilters.swift Sources/RuleData.swift Sources/WorkshopCore.swift Sources/WorkshopModel.swift Sources/WorkshopView.swift Sources/BuildEditor.swift Sources/WorkshopTools.swift Sources/LabCore.swift Sources/ProbabilityCore.swift Sources/LabModel.swift Sources/ProbabilityView.swift Sources/PlayViews.swift Sources/CollectionTools.swift Sources/TrendsView.swift Sources/AdvancedCore.swift Sources/Recovery.swift Sources/AdvancedViews.swift Sources/OrganizationViews.swift Sources/ShareView.swift Sources/DesignSystem.swift Sources/App.swift -o "$APP/Contents/MacOS/DeckLab"
cp Resources/DeckLab.icns "$APP/Contents/Resources/DeckLab.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIconFile</key><string>DeckLab</string>
<key>CFBundleName</key><string>Deck Lab</string>
<key>CFBundleDisplayName</key><string>Deck Lab</string>
<key>CFBundleIdentifier</key><string>com.local.decklab</string>
<key>CFBundleExecutable</key><string>DeckLab</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>6.3</string>
<key>CFBundleVersion</key><string>12</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "Built $APP"
