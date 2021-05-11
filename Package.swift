// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LocalConsole",
    platforms: [
        .iOS(.v14),
    ],
    products: [
        .library(
            name: "LocalConsole", targets: ["LocalConsole"]),
    ],
    targets: [
        .target(name: "LocalConsole", dependencies: [])
    ]
)
