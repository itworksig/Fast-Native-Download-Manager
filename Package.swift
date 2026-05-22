// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FastNativeDownloadManager",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "FastNativeDownloadManager",
            targets: ["FastNativeDownloadManager"]
        )
    ],
    targets: [
        .executableTarget(
            name: "FastNativeDownloadManager",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
