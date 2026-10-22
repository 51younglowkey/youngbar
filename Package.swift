// swift-tools-version: 6.0
// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only
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
