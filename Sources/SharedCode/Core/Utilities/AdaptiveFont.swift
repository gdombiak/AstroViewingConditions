import SwiftUI

struct AdaptiveFontModifier: ViewModifier {
#if os(watchOS)
    func body(content: Content) -> some View {
        content
    }
#else
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    func body(content: Content) -> some View {
        let isLandscape = verticalSizeClass == .compact
        let isRegular = horizontalSizeClass == .regular
        
        if isRegular {
            content
                .dynamicTypeSize(.xxxLarge)
        } else if isLandscape {
            content
                .dynamicTypeSize(.large)
        } else {
            content
        }
    }
#endif
}

extension View {
    func adaptiveFonts() -> some View {
        modifier(AdaptiveFontModifier())
    }
}
