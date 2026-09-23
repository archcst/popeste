// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Popaste", platforms: [.macOS(.v13)], products: [.executable(name: "Popaste", targets: ["Popaste"])], targets: [.executableTarget(name: "Popaste", exclude: ["Resources/interface.js", "Resources/search-input.js", "Resources/localization.js", "Resources/vim-editor.js"], resources: [.copy("Resources/interface.html")])])
