import SwiftUI

private struct PopoverSizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// Renders `content` at `scale` and reports a correspondingly smaller layout
/// size, so the whole popover shrinks uniformly — width, fonts, spacing and
/// every element scale together, which means nothing can overflow or fall out of
/// alignment. Used to make the menu-bar popover ~20% smaller in both dimensions.
///
/// `fixedSize(vertical:)` pins the content to its natural height before scaling,
/// which both lets the inner ScrollView expand to its content and prevents a
/// measure→frame→measure feedback loop.
struct ScaledPopover<Content: View>: View {
    var scale: CGFloat
    @ViewBuilder var content: Content
    @State private var natural = CGSize(width: DT.Size.popoverWidth, height: 620)

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: PopoverSizeKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(PopoverSizeKey.self) { newSize in
                if newSize.width > 0, newSize.height > 0 { natural = newSize }
            }
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: natural.width * scale,
                   height: natural.height * scale,
                   alignment: .topLeading)
    }
}
