// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Shitie",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Shitie", targets: ["Shitie"])],
    targets: [
        .target(name: "ShitieCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "Shitie", dependencies: ["ShitieCore"]),
        // A dependency-free executable suite also works with Command Line Tools, which omit XCTest.
        .executableTarget(name: "ShitieChecks", dependencies: ["ShitieCore"], path: "Tests/ShitieCoreTests")
    ]
)
