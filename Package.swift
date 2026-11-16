// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Slowburn",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "quota", targets: ["quota"]),
        .executable(name: "Slowburn", targets: ["SlowburnApp"]),
    ],
    dependencies: [
        // In-app updates: checks the appcast, downloads, verifies the EdDSA signature, installs and relaunches.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Pure pacing math: no IO, no clocks. Everything time-dependent takes `now`.
        .target(name: "BudgetCore"),
        // Readers for provider data, the shared state file and the monitor loop.
        .target(name: "QuotaKit", dependencies: ["BudgetCore"]),
        .executableTarget(name: "quota", dependencies: ["QuotaKit"]),
        .executableTarget(name: "SlowburnApp", dependencies: ["QuotaKit", .product(name: "Sparkle", package: "Sparkle")],
                          // Inside Slowburn.app, Sparkle.framework sits in Contents/Frameworks.
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "BudgetCoreTests", dependencies: ["BudgetCore"]),
        .testTarget(name: "QuotaKitTests", dependencies: ["QuotaKit"]),
    ],
    swiftLanguageModes: [.v5]
)
