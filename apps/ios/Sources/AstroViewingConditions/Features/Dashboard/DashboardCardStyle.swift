import SwiftUI

struct DashboardCardStyle: ViewModifier {
    @Environment(\.appPalette) private var palette

    @ViewBuilder
    func body(content: Content) -> some View {
        if palette.appearance == .field {
            content
                .padding()
                .background(palette.elevatedBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(palette.border, lineWidth: 1)
                }
        } else {
            content
                .padding()
                .background(Color(uiColor: .systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

extension View {
    func dashboardCardStyle() -> some View {
        modifier(DashboardCardStyle())
    }
}
