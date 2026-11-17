// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KnowledgeStudio",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "KnowledgeCore", targets: ["KnowledgeCore"])],
    targets: [
        .target(name: "KnowledgeCore"),
        .testTarget(name: "KnowledgeCoreTests", dependencies: ["KnowledgeCore"])
    ]
)
