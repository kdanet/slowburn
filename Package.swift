// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Slowburn",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "quota", targets: ["quota"]),
        .executable(name: "Slowburn", targets: ["SlowburnApp"]),
    ],
    targets: [
        // Pure pacing math: no IO, no clocks. Everything time-dependent takes `now`.
        .target(name: "BudgetCore"),
        // Readers for provider data, the shared state file and the monitor loop.
        .target(name: "QuotaKit", dependencies: ["BudgetCore"]),
        .executableTarget(name: "quota", dependencies: ["QuotaKit"]),
        .executableTarget(name: "SlowburnApp", dependencies: ["QuotaKit"]),
        .testTarget(name: "BudgetCoreTests", dependencies: ["BudgetCore"]),
        .testTarget(name: "QuotaKitTests", dependencies: ["QuotaKit"]),
    ],
    swiftLanguageModes: [.v5]
)
