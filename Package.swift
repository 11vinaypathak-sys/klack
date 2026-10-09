// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Klack",
    platforms: [.macOS(.v12)],
    targets: [
        // Objective-C shim: AVAudioEngine raises NSException on invalid
        // state, which Swift cannot catch, so such a throw terminates the
        // whole app rather than failing locally.
        .target(
            name: "KlackObjC",
            path: "Sources/KlackObjC"
        ),
        // The brand mark, shared by the icon generator and the app itself so
        // the two can't drift apart.
        .target(
            name: "KlackBrand",
            path: "Sources/KlackBrand"
        ),
        .executableTarget(
            name: "Klack",
            dependencies: ["KlackObjC", "KlackBrand"],
            path: "Sources/Klack"
        ),
        .executableTarget(
            name: "KlackDiag",
            path: "Sources/KlackDiag"
        ),
        .executableTarget(
            name: "OverlayGen",
            dependencies: ["KlackBrand"],
            path: "Sources/OverlayGen"
        ),
        .executableTarget(
            name: "IconGen",
            dependencies: ["KlackBrand"],
            path: "Sources/IconGen"
        )
    ]
)
