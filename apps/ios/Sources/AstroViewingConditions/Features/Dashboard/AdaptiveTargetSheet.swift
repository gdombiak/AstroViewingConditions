import SwiftUI

enum TargetSheetLayout {
    static let regularWidth: CGFloat = 720

    static func preferredWidth(for horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat? {
        horizontalSizeClass == .regular ? regularWidth : nil
    }
}

extension View {
    @ViewBuilder
    func adaptiveTargetSheet(
        horizontalSizeClass: UserInterfaceSizeClass?,
        prefersTallerPresentation: Bool = false
    ) -> some View {
        if let width = TargetSheetLayout.preferredWidth(for: horizontalSizeClass) {
            if prefersTallerPresentation {
                frame(width: width)
                    .presentationSizing(.page.fitted(horizontal: true, vertical: false))
            } else {
                frame(width: width)
                    .presentationSizing(.form.fitted(horizontal: true, vertical: false))
            }
        } else {
            self
        }
    }
}
