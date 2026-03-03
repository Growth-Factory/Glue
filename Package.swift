// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Glue",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "GlueMemory", targets: ["GlueMemory"]),
        .library(name: "GluePostgres", targets: ["GluePostgres"]),
        .library(name: "GlueLLM", targets: ["GlueLLM"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/mattt/AnyLanguageModel.git", from: "0.7.0"),
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.12.0"),
    ],
    targets: [
        .target(
            name: "GlueMemory",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "GluePostgres",
            dependencies: [
                "GlueMemory",
                .product(name: "PostgresNIO", package: "postgres-nio"),
            ]
        ),
        .target(
            name: "GlueLLM",
            dependencies: [
                "GlueMemory",
                .product(name: "AnyLanguageModel", package: "AnyLanguageModel"),
            ]
        ),
        .testTarget(
            name: "GlueMemoryTests",
            dependencies: [
                "GlueMemory",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
        .testTarget(
            name: "GluePostgresTests",
            dependencies: [
                "GluePostgres",
                "GlueMemory",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
        .testTarget(
            name: "GlueLLMTests",
            dependencies: [
                "GlueLLM",
                "GlueMemory",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
