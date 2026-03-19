# Deploying & Running NutriVisionAI

## Web App

```bash
source .venv/bin/activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Open http://localhost:8000 in your browser.

---

## iOS App (Xcode Simulator)

### Prerequisites

- **macOS** with **Xcode 15.0+** installed (from the App Store)
- **Xcode Command Line Tools**: `xcode-select --install`
- **Homebrew**: https://brew.sh

### Step 1: Install xcodegen

```bash
brew install xcodegen
```

### Step 2: Generate the Xcode project

```bash
cd ios/NutriVisionAI
xcodegen generate
```

This creates `NutriVisionAI.xcodeproj` from `project.yml`.

Or use the setup script which does both steps automatically:

```bash
cd ios
chmod +x scripts/setup.sh
./scripts/setup.sh
```

### Step 3: Start the backend server

The iOS app needs the Python backend running. In a separate terminal:

```bash
source .venv/bin/activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### Step 4: Open in Xcode and run on simulator

```bash
open ios/NutriVisionAI/NutriVisionAI.xcodeproj
```

In Xcode, look at the **top toolbar** — you'll see a scheme/device selector that looks like:
`NutriVisionAI > iPhone 16 Pro`

1. **Select the scheme** — click the **left part** of the selector and choose:
   - `NutriVisionAI` — Backend API mode (iOS 17+, recommended)
   - `NutriVisionAI-AppleAI` — Apple Foundation Models mode (iOS 26+, requires Xcode 26 beta)

2. **Select a simulator** — click the **right part** (device name) and pick any iPhone listed under "iOS Simulators" (e.g. iPhone 16 Pro, iPhone 15, etc.)

3. **Press Cmd+R** (or click the **play button** in the top-left corner) to build and run

Xcode will compile the project and automatically launch the iOS Simulator with the app running. The first build takes a minute or two; subsequent builds are faster.

Since the simulator runs on your Mac, it connects to the backend at `http://localhost:8000` by default — no extra network configuration needed.

### Alternative: Build from command line

```bash
cd ios
chmod +x scripts/build.sh
./scripts/build.sh backend debug
```

This builds for the iPhone 16 Pro simulator. Then open Xcode to run it.

---

## Connecting a Physical iPhone

If running on a real device instead of the simulator:

1. In the app's **Settings** tab, update the **Server URL** to your Mac's local IP:
   ```
   http://192.168.x.x:8000
   ```
   (Find your IP with `ifconfig en0 | grep inet`)

2. The app already has `NSAllowsLocalNetworking` enabled in Info.plist, so HTTP connections to local network addresses work without issues.

3. You'll need an Apple Developer account to sign the app for device deployment. In Xcode: Signing & Capabilities > Team > select your account.

---

## Build Configurations

| Scheme | Config | iOS Target | Description |
|--------|--------|-----------|-------------|
| `NutriVisionAI` | Debug | 17.0+ | Backend API, debug build |
| `NutriVisionAI` | Release | 17.0+ | Backend API, release build |
| `NutriVisionAI-AppleAI` | Debug-AppleAI | 26.0+ | On-device Apple AI, debug |
| `NutriVisionAI-AppleAI` | Release-AppleAI | 26.0+ | On-device Apple AI, release |

The Apple Foundation Models build uses on-device AI for food analysis (no server needed for that feature), but still requires the backend for data storage, history, and settings.

---

## Troubleshooting

**"No module named 'app'"** when starting the server
— Make sure you activated the virtualenv: `source .venv/bin/activate`

**Simulator can't connect to backend**
— Verify the server is running on port 8000
— Check the app's Settings > Server URL is `http://localhost:8000`

**xcodegen: command not found**
— Run `brew install xcodegen`

**Build fails with "No such module 'FoundationModels'"**
— You're using the AppleAI scheme but don't have Xcode 26 beta. Switch to the regular `NutriVisionAI` scheme instead.
