// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PelmetEngine",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "PelmetEngine", targets: ["PelmetEngine"]),
    ],
    dependencies: [
        .package(path: "../PelmetCore"),
    ],
    targets: [
        // ObjC shim: dlopen/NSClassFromString access to MenuBarClientCore's
        // assessment-mode classes. Kept ObjC so exceptions from private API
        // calls can be caught (@try/@catch) without tearing the process down.
        .target(
            name: "PelmetEngineObjC",
            path: "Sources/PelmetEngineObjC"
        ),
        .target(
            name: "PelmetEngine",
            dependencies: [
                "PelmetEngineObjC",
                .product(name: "PelmetCore", package: "PelmetCore"),
            ],
            path: "Sources/PelmetEngine"
        ),
    ]
)
