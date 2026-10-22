// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YoungBar",
    platforms: [.macOS("27.0")],
    products: [.executable(name: "YoungBar", targets: ["YoungBar"])],
    dependencies: [
        .package(path: "Vendor/PelmetCore"),
        .package(path: "Vendor/PelmetEngine"),
    ],
    targets: [
        .executableTarget(
            name: "YoungBar",
            dependencies: [
                .product(name: "PelmetEngine", package: "PelmetEngine"),
                .product(name: "PelmetCore", package: "PelmetCore"),
            ]
        ),
    ]
)
