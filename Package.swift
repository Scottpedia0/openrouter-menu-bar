// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenRouterMenuBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "OpenRouterMenuBar",
            targets: ["OpenRouterMenuBar"]
        )
    ],
    targets: [
        .executableTarget(
            name: "OpenRouterMenuBar",
            path: "Sources"
        )
    ]
)
