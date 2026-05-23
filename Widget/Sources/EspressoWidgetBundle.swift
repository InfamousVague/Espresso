import WidgetKit
import SwiftUI

/// `@main` for the Espresso widget extension. WidgetBundle is required
/// even when shipping a single widget — WidgetKit uses it to
/// enumerate what the extension provides to the macOS widget gallery.
@main
struct EspressoWidgetBundle: WidgetBundle {
    var body: some Widget {
        EspressoStatusWidget()
    }
}
