// swift-tools-version: 6.1

import PackageDescription

// FanCurveCore, FanCurveCheck, and the test suite build anywhere (pure Swift
// plus Foundation). The rest need IOKit and AppKit, so they only exist on macOS;
// that keeps `swift build` and `swift test` working on Linux for the portable
// core, which is what the Linux checks run. On macOS the target set is unchanged.
var targets: [Target] = [
    .target(name: "FanCurveCore"),
    .executableTarget(
        name: "FanCurveCheck",
        dependencies: ["FanCurveCore"]
    ),
    .executableTarget(
        name: "FanCurveCurve",
        dependencies: ["FanCurveCore"]
    ),
    .testTarget(
        name: "FanCurveCoreTests",
        dependencies: ["FanCurveCore"]
    )
]

var products: [Product] = [
    .executable(name: "fan-curve-curve", targets: ["FanCurveCurve"])
]

#if os(macOS)
targets += [
    .target(
        name: "StatsSMC",
        path: "Vendor/Stats/SMC",
        exclude: ["Helper", "Makefile", "main.swift"],
        sources: ["smc.swift"],
        linkerSettings: [.linkedFramework("IOKit")]
    ),
    .target(
        name: "FanCurveUI",
        dependencies: ["FanCurveCore"]
    ),
    .executableTarget(
        name: "FanCurveApp",
        dependencies: ["FanCurveCore", "FanCurveUI", "StatsSMC"]
    ),
    .executableTarget(
        name: "FanCurveHelper",
        dependencies: ["FanCurveCore", "StatsSMC"]
    ),
    .executableTarget(
        name: "FanCurveProbe",
        dependencies: ["FanCurveCore", "StatsSMC"]
    ),
    .executableTarget(name: "FanCurveAppCheck", dependencies: ["FanCurveUI"])
]

products += [
    .executable(name: "FanCurveApp", targets: ["FanCurveApp"]),
    .executable(name: "FanCurveHelper", targets: ["FanCurveHelper"]),
    .executable(name: "FanCurveProbe", targets: ["FanCurveProbe"])
]
#endif

let package = Package(
    name: "FanCurve",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets,
    swiftLanguageModes: [.v5]
)
