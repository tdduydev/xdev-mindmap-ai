import SwiftUI

extension View {
    /// Fills `handle` with the window this view is in, so other windows can
    /// bring it to the front.
    func windowHandle(_ handle: WindowHandle) -> some View {
        background(WindowReader(handle: handle))
    }
}
