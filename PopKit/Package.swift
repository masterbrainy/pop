// swift-tools-version: 6.0
import PackageDescription

// Pure logic for Pop!, kept free of UIKit and SwiftUI so it builds and tests on macOS.
let package = Package(
    name: "PopKit",
    platforms: [.iOS("27.1"), .macOS(.v15)],
    products: [
        .library(name: "PopKit", targets: ["PopKit"]),
    ],
    targets: [
        .target(name: "PopKit"),
        .testTarget(name: "PopKitTests", dependencies: ["PopKit"]),
    ]
)
