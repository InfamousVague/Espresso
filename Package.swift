// swift-tools-version: 5.9
import PackageDescription

// Espresso ships THREE products from one source tree:
//
//  • `EspressoPane` — dynamic library (store, UI, keep-awake engine)
//    exposed through SuiteKit. Embedded in
//    Espresso.app/Contents/Frameworks so the MattsSoftware launcher
//    can load the same code out of an installed Espresso.
//
//  • `Espresso` — thin @main shim hosting that pane in its own
//    NSStatusItem/NSPopover (standalone app).
//
//  • `EspressoShared` — static library with App Group id, the
//    `SharedStats` Group-Container model, `ToggleEspressoIntent`,
//    `IntentBus`, and `WidgetSignal` Darwin helpers. Consumed by
//    `EspressoPane`, `Espresso`, AND the Xcode widget target at
//    `Widget/EspressoWidgets.xcodeproj` — the widget extension can't
//    live in SPM (SR-14944: SPM has no
//    `productType = com.apple.product-type.app-extension`, the
//    binary fatal-errors in ExtensionFoundation at launch). The
//    Xcode subproject consumes `EspressoShared` via local package
//    dependency so the widget shares one source of truth for the
//    models + intent definitions.
let package = Package(
    name: "Espresso",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Espresso", targets: ["Espresso"]),
        .library(name: "EspressoPane", type: .dynamic, targets: ["EspressoPane"]),
        .library(name: "EspressoShared", targets: ["EspressoShared"])
    ],
    dependencies: [
        .package(path: "../suitekit-swift")
    ],
    targets: [
        .target(
            name: "EspressoShared",
            path: "Sources/EspressoShared"
        ),
        .target(
            name: "EspressoPane",
            dependencies: [
                "EspressoShared",
                .product(name: "SuiteKit", package: "suitekit-swift")
            ],
            path: "Sources/EspressoPane"
        ),
        .executableTarget(
            name: "Espresso",
            dependencies: [
                "EspressoPane",
                "EspressoShared",
                .product(name: "SuiteKit", package: "suitekit-swift")
            ],
            path: "Sources/Espresso"
        )
    ]
)
