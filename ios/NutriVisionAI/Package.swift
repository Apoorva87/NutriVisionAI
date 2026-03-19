// swift-tools-version: 5.9
// This is provided for reference. For the iOS app, create an Xcode project:
//   1. Open Xcode → File → New → Project → iOS App
//   2. Set location to ios/NutriVisionAI/
//   3. Drag existing Models/, Services/, Views/ groups into the project
//   4. The source files are already here — no need to create new ones.
//
// Alternatively, use `xcodegen` with the project.yml below.

import PackageDescription

let package = Package(
    name: "NutriVisionAI",
    platforms: [.iOS(.v17)],
    targets: [
        .executableTarget(
            name: "NutriVisionAI",
            path: "."
        ),
    ]
)
