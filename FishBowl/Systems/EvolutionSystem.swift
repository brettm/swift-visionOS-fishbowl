rm -rf ./DerivedData
xcodebuild -project FishBowl.xcodeproj -scheme HoloDeck CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
