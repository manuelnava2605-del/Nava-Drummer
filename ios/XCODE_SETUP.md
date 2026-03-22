# NavaDrummer — iOS Xcode Setup

## Quick Setup (5 minutes)

1. **Open terminal in project root:**
```bash
cd nava_drummer
flutter pub get
cd ios && pod install && cd ..
```

2. **Open in Xcode:**
```bash
open ios/Runner.xcworkspace
```

3. **Configure Bundle ID:**
   - Runner target → General → Bundle Identifier: `com.yourcompany.navadrummer`

4. **Add Google Services:**
   - Drag `GoogleService-Info.plist` into Runner/ folder in Xcode
   - Check "Copy items if needed"

5. **Set Development Team:**
   - Runner → Signing & Capabilities → Team: select your Apple Developer account

6. **StoreKit (In-App Purchases):**
   - Runner → Signing & Capabilities → + Capability → In-App Purchase

7. **Build & Run:**
```bash
flutter run --release
```

## App Store Submission Checklist
- [ ] Bundle ID matches App Store Connect
- [ ] Version/Build number incremented
- [ ] Privacy manifest (PrivacyInfo.xcprivacy) added
- [ ] App Store screenshots (6.7", 6.5", 5.5", iPad)
- [ ] Privacy Policy URL in App Store Connect
- [ ] Age rating configured
- [ ] RevenueCat iOS key set in subscription_service.dart
