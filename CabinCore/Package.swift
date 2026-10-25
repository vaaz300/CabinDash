// swift-tools-version: 5.9
import PackageDescription

// CabinCore holds everything in Cabin Dash that does not need UIKit or SwiftUI:
// the app catalog, App Store matching, shelf rules, speed and trip maths, and preferences.
// Keeping it separate means it can be unit tested without a simulator (`swift test`).
let package = Package(
    name: "CabinCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CabinCore", targets: ["CabinCore"])
    ],
    targets: [
        .target(name: "CabinCore"),
        .testTarget(name: "CabinCoreTests", dependencies: ["CabinCore"])
    ]
)
