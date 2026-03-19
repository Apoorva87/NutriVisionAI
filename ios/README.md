# NutriVisionAI iOS App

Native iOS app for NutriVisionAI - AI-powered food nutrition tracking.

## Requirements

- **macOS** 14.0+ (Sonoma or later)
- **Xcode** 15.0+ (for iOS 17 builds) or Xcode 16.0+ (for iOS 26/Apple AI builds)
- **iOS Device/Simulator** iOS 17.0+ (or iOS 26+ for Apple Foundation Models)
- **Homebrew** (for xcodegen installation)

## Quick Start

### 1. Run Setup Script

```bash
cd ios
chmod +x scripts/setup.sh
./scripts/setup.sh
```

This will:
- Install xcodegen if needed
- Generate the Xcode project
- Display available build configurations

### 2. Open in Xcode

```bash
open NutriVisionAI/NutriVisionAI.xcodeproj
```

### 3. Select Scheme and Run

1. Choose your target scheme from the scheme selector:
   - **NutriVisionAI** - Backend API (default)
   - **NutriVisionAI-AppleAI** - Apple Foundation Models (iOS 26+)
2. Select a simulator or connected device
3. Press `Cmd+R` to build and run

## Build Configurations

### Backend API (Default)

Uses your NutriVision backend server for AI-powered food analysis. This is the recommended configuration for most users.

| Configuration | iOS Version | Use Case |
|--------------|-------------|----------|
| Debug | 17.0+ | Development and testing |
| Release | 17.0+ | App Store / TestFlight |

**Build command:**
```bash
./scripts/build.sh backend debug
./scripts/build.sh backend release
```

**Pros:**
- Works on iOS 17+
- More accurate (uses powerful cloud AI models)
- Easy to update AI models without app update
- Consistent with web app

**Requirements:**
- Backend server running (locally or deployed)
- Network connectivity

### Apple Foundation Models (iOS 26+)

Uses Apple's on-device Foundation Models for food image analysis. No server required for the image analysis step.

| Configuration | iOS Version | Use Case |
|--------------|-------------|----------|
| Debug-AppleAI | 26.0+ | Development with Apple AI |
| Release-AppleAI | 26.0+ | Distribution with Apple AI |

**Build command:**
```bash
./scripts/build.sh apple-ai debug
./scripts/build.sh apple-ai release
```

**Pros:**
- Works offline (for image analysis)
- Privacy-focused (images analyzed on-device)
- No API costs for image analysis

**Requirements:**
- iOS 26+ (currently in beta)
- Apple Silicon device (A17 Pro+, M1+)
- Backend still needed for: meal logging, history, user accounts

## Project Structure

```
ios/
├── NutriVisionAI/
│   ├── Views/
│   │   ├── ContentView.swift      # Tab navigation
│   │   ├── DashboardView.swift    # Home/summary screen
│   │   ├── AnalyzeView.swift      # Camera + AI analysis
│   │   ├── LogView.swift          # Food search + meal builder
│   │   ├── HistoryView.swift      # Trends and past meals
│   │   └── SettingsView.swift     # App configuration
│   ├── Models/
│   │   └── NutritionModels.swift  # API data models
│   ├── Services/
│   │   ├── APIClient.swift        # Backend HTTP client
│   │   └── FoodAnalysisService.swift  # AI provider abstraction
│   ├── Supporting/
│   │   └── Info.plist             # App configuration
│   ├── NutriVisionAIApp.swift     # App entry point
│   └── project.yml                # XcodeGen configuration
├── scripts/
│   ├── setup.sh                   # Initial setup script
│   └── build.sh                   # Build automation script
└── README.md                      # This file
```

## Connecting to Backend

### Simulator (localhost)

The app defaults to `http://localhost:8000`. If your backend runs on a different port, update it in Settings > Connection.

### Physical Device

When running on a physical iPhone/iPad, you need to use your Mac's IP address:

1. Find your Mac's IP: System Settings > Network > Wi-Fi > Details > IP Address
2. In the iOS app: Settings > Connection > Server URL
3. Enter: `http://YOUR_MAC_IP:8000`
4. Tap "Test Connection" to verify

**Example:** `http://192.168.1.100:8000`

### Deployed Backend

If your backend is deployed (e.g., on Vercel), use the deployment URL:

```
https://your-app.vercel.app
```

## Features

### Dashboard
- Animated calorie ring showing daily progress
- Macro nutrient bars (protein, carbs, fat)
- Recent meals list with swipe-to-delete

### Scan (Analyze)
- Camera capture or photo library selection
- AI-powered food detection
- Editable portions with multipliers
- Save meals with custom names

### Log
- Food database search
- Custom foods from your history
- AI text-based food lookup
- Manual meal builder with live nutrition totals

### History
- Calorie trend chart (7/14/30 days)
- Expandable daily meal sections
- Top foods ranking

### Settings
- Account management (sign in/out)
- Nutrition goals configuration
- AI provider selection (Backend/Apple)
- Server URL configuration
- Connection testing

## Switching AI Providers

You can switch between AI providers in two ways:

### 1. Build-time (Compile Flag)

Choose the scheme when building:
- `NutriVisionAI` - Only backend provider available
- `NutriVisionAI-AppleAI` - Both providers available

### 2. Runtime (In-App)

When using the AppleAI build, users can switch between providers:
- Go to Settings > Image Analysis
- Select "Backend API" or "Apple Foundation Models"

## Troubleshooting

### "xcodegen not found"

```bash
brew install xcodegen
```

### "Signing certificate" errors

1. Open Xcode > Settings > Accounts
2. Add your Apple ID
3. Select the project > Signing & Capabilities
4. Select your team

### "Cannot connect to server"

1. Ensure backend is running
2. Check firewall settings
3. For device: use Mac's IP, not `localhost`
4. Test connection in Settings

### "Apple Foundation Models unavailable"

- Requires iOS 26+ and Apple Silicon
- Only available in `*-AppleAI` configurations
- Device must support on-device ML

### Build fails with "module not found"

Regenerate the project:
```bash
cd NutriVisionAI
xcodegen generate
```

## Development

### Regenerate Xcode Project

After modifying `project.yml`:

```bash
cd NutriVisionAI
xcodegen generate
```

### Adding New Files

1. Create the Swift file in the appropriate folder
2. Run `xcodegen generate` to update the project
3. Or manually add via Xcode (will be lost on next generate)

### Code Style

- SwiftUI with iOS 17+ features
- Async/await for all network calls
- `@State` / `@StateObject` for view state
- SF Symbols for all icons
- System colors for theming

## License

Part of the NutriVisionAI project.
