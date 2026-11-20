// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KnowledgeStudio",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "KnowledgeCore", targets: ["KnowledgeCore"])],
    dependencies: [
        .package(url: "https://github.com/open-spaced-repetition/swift-fsrs.git", exact: "6.0.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.12.0"),
        .package(url: "https://github.com/ajevans99/swift-json-schema.git", exact: "0.15.0"),
    ],
    targets: [
        .target(
            name: "KnowledgeCore",
            dependencies: [
                .product(name: "FSRS", package: "swift-fsrs"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "JSONSchema", package: "swift-json-schema"),
            ], resources: [.copy("Resources")]),
        .testTarget(name: "KnowledgeCoreTests", dependencies: ["KnowledgeCore"]),
    ]
)
