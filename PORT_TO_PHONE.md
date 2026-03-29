# Installing NutriVisionAI on a Physical iPhone

## Prerequisites

- An Apple ID (free accounts work, but apps expire after 7 days)
- iPhone connected via USB (Lightning or USB-C)
- Xcode installed on your Mac

## Steps

### 1. Open the Xcode project

```bash
cd ios/NutriVisionAI
xcodegen generate
open NutriVisionAI.xcodeproj
```

### 2. Set up code signing

1. In Xcode, select the **NutriVisionAI** target
2. Go to **Signing & Capabilities**
3. Check **Automatically manage signing**
4. Select your **Team** (your Apple ID)
5. If the bundle identifier conflicts, change it to something unique (e.g. `com.yourname.NutriVisionAI`)

### 3. Select your device

1. Connect your iPhone via USB
2. Trust the computer on your iPhone if prompted
3. In Xcode's toolbar, select your iPhone from the device dropdown

### 4. Build and run

1. Press **Cmd+R** or click the Play button
2. First time: you may need to trust the developer on your iPhone:
   - Go to **Settings > General > VPN & Device Management**
   - Tap your developer account and tap **Trust**
3. The app should launch on your phone

## Troubleshooting

- **"Untrusted Developer"**: See step 4.2 above
- **Signing errors**: Make sure your Apple ID is added in Xcode > Settings > Accounts
- **Device not showing**: Make sure the phone is unlocked and you've trusted the computer
- **Free account limitations**: Apps expire after 7 days; re-run from Xcode to reinstall
