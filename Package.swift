// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Popaste", platforms: [.macOS(.v14)], products: [.executable(name: "Popaste", targets: ["Popaste"])], targets: [.executableTarget(name: "Popaste", exclude: ["Resources"])])
