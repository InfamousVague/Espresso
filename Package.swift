// swift-tools-version: 5.9
import PackageDescription

// Espresso ships TWO products from one source tree:
//
//  • `EspressoPane` — a dynamic library (the whole feature: store,
//    UI, keep-awake engine) exposed through SuiteKit. It is embedded
//    in Espresso.app/Contents/Frameworks so the MattsSoftware
//    launcher can load it out of an installed Espresso and show it
//    as a pane — no separate copy of the code in the launcher.
//
//  • `Espresso` — a thin @main shim that hosts that same pane in its
//    own NSStatusItem/NSPopover. This is the standalone app, and its
//    behaviour is unchanged from before the split.
let package = Package(
    name: "Espresso",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Espresso", targets: ["Espresso"]),
        .library(name: "EspressoPane", type: .dynamic, targets: ["EspressoPane"])
    ],
    dependencies: [
        .package(path: "../suitekit-swift")
    ],
    targets: [
        .target(
            name: "EspressoPane",
            dependencies: [.product(name: "SuiteKit", package: "suitekit-swift")],
            path: "Sources/EspressoPane"
        ),
        .executableTarget(
            name: "Espresso",
            dependencies: [
                "EspressoPane",
                .product(name: "SuiteKit", package: "suitekit-swift")
            ],
            path: "Sources/Espresso"
        )
    ]
)
