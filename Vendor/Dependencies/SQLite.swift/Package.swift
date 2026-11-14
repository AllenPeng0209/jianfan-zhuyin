// swift-tools-version:5.9
import PackageDescription

// This distribution targets macOS and uses the system SQLite library.
let deps: [Package.Dependency] = []

let targets: [Target] = [
    .target(
        name: "SQLite",
        dependencies: [],
        exclude: [
            "Info.plist"
        ]
    )
]

let testTargets: [Target] = [
    .testTarget(
        name: "SQLiteTests",
        dependencies: [
            "SQLite"
        ],
        path: "Tests/SQLiteTests",
        exclude: [
            "Info.plist"
        ],
        resources: [
            .copy("Resources")
        ]
    )
]

let package = Package(
    name: "SQLite.swift",
    platforms: [
        .iOS(.v12),
        .macOS(.v10_13),
        .watchOS(.v4),
        .tvOS(.v12),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "SQLite",
            targets: ["SQLite"]
        )
    ],
    dependencies: deps,
    targets: targets + testTargets
)

extension Package.Dependency {

    static func github(_ repo: String, exact ver: Version) -> Package.Dependency {
        .package(url: "https://github.com/\(repo)", exact: ver)
    }
}
