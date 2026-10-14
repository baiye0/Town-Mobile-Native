// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "TownCore", platforms: [.macOS(.v14)], products: [.library(name: "TownCore", targets: ["TownCore"])], targets: [.target(name: "TownCore", path: "ios/Town/Core"), .testTarget(name: "TownCoreTests", dependencies: ["TownCore"])])
