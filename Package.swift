// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Klack",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "Klack",
            path: "Sources/Klack"
        ),
        .executableTarget(
            name: "KlackDiag",
            path: "Sources/KlackDiag"
        ),
        .executableTarget(
            name: "IconGen",
            path: "Sources/IconGen"
        )
    ]
)
