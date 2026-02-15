// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "StraightenUp",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "StraightenUpLib",
            path: "Sources/StraightenUpLib"
        ),
        .executableTarget(
            name: "StraightenUp",
            dependencies: ["StraightenUpLib"],
            path: "Sources/StraightenUp",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Info.plist"
                ])
            ]
        ),
        .executableTarget(
            name: "StraightenUpTests",
            dependencies: ["StraightenUpLib"],
            path: "Tests/StraightenUpTests"
        )
    ]
)
