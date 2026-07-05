import SwiftUI

struct DashboardCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(Color(uiColor: .systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

extension View {
    func dashboardCardStyle() -> some View {
        modifier(DashboardCardStyle())
    }
}
