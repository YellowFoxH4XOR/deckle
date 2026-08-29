// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Deckle",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Deckle",
            path: "Sources/Deckle"
        ),
        .testTarget(
            name: "DeckleTests",
            dependencies: ["Deckle"],
            path: "Tests/DeckleTests"
        )
    ]
)
