import UIKit

/// Minimal app-level delegate. The reader needs per-scene interface-orientation
/// overrides (portrait-only on iPhone by default, landscape while reading); this
/// is the only app-delegate responsibility that remains after the RSS / Firebase
/// integrations were removed.
final class AppOrientationDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        ReaderOrientationController.shared.supportedMask(for: UIDevice.current.userInterfaceIdiom)
    }
}
