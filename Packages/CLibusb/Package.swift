// swift-tools-version: 6.0

import PackageDescription

// Vendored libusb 1.0.30 (LGPL-2.1-or-later) built for macOS.
// Sources are compiled straight into the app so no system package is required.
let package = Package(
    name: "CLibusb",
    products: [
        .library(name: "CLibusb", targets: ["CLibusb"])
    ],
    targets: [
        .target(
            name: "CLibusb",
            cSettings: [
                .define("HAVE_CONFIG_H"),
                .headerSearchPath("."),
                .headerSearchPath("include"),
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Security"),
            ]
        )
    ]
)
