// swift-tools-version:5.9
import PackageDescription

// Test-only package: compiles the wire protocol shared with FWPlayer (no UI) so it can
// be unit-tested with `swift test` on a Mac. The app itself is still built from
// FWPlayerRemote.xcodeproj.
let package = Package(
    name: "FWRemoteProtocol",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FWRemoteProtocol", path: "Sources/Protocol"),
        .testTarget(name: "FWRemoteProtocolTests", dependencies: ["FWRemoteProtocol"],
                    path: "Tests/FWRemoteProtocolTests"),
    ]
)
