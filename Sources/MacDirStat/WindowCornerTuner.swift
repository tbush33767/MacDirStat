import AppKit
import ObjectiveC

/// Tightens the window corner radius app-wide (macOS 26 default is 26 pt).
///
/// There is no public API: AppKit computes each window's shape from the
/// private `-[NSThemeFrame _cornerRadius]`. We replace that implementation
/// before any window exists, so every window this app creates picks up the
/// tighter radius naturally (shape, shadow, and clipping all follow).
/// Purely cosmetic and version-fragile by nature — if a future macOS drops
/// the selector, this silently does nothing.
enum WindowCornerStyle {
    static func install(radius: CGFloat) {
        guard let frameClass = NSClassFromString("NSThemeFrame"),
              let method = class_getInstanceMethod(frameClass, NSSelectorFromString("_cornerRadius"))
        else { return }
        let block: @convention(block) (NSObject) -> CGFloat = { frameView in
            // Fullscreen windows must stay square.
            if let view = frameView as? NSView,
               view.window?.styleMask.contains(.fullScreen) == true {
                return 0
            }
            return radius
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }
}
