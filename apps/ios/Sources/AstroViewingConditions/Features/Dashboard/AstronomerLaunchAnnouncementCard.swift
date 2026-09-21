import SwiftUI

struct AstronomerLaunchAnnouncementCard: View {
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(AstronomerLaunchAnnouncement.title, systemImage: AstronomerSettingsEntry.systemImage)
                .font(.subheadline.weight(.medium))
                .accessibilityAddTraits(.isHeader)

            Text(AstronomerLaunchAnnouncement.summary)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            Text(AstronomerLaunchAnnouncement.grokRequirement)
                .font(.subheadline)
                .appSecondaryForeground()
                .fixedSize(horizontal: false, vertical: true)

            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCardStyle()
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                openButton
                dismissButton
            }
            VStack(alignment: .leading, spacing: 8) {
                openButton
                dismissButton
            }
        }
    }

    private var openButton: some View {
        Button(AstronomerLaunchAnnouncement.openActionTitle, action: onOpen)
            .appPrimaryActionStyle()
            .accessibilityAddTraits(.isLink)
            .accessibilityHint(AstronomerLaunchAnnouncement.openActionHint)
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Text(AstronomerLaunchAnnouncement.dismissActionTitle)
                .font(.subheadline.weight(.semibold))
                .appSecondaryForeground()
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityHint(AstronomerLaunchAnnouncement.dismissActionHint)
    }
}

#Preview("Announcement") {
    AstronomerLaunchAnnouncementCard(onOpen: {}, onDismiss: {})
        .padding()
}

#Preview("Announcement Dark") {
    AstronomerLaunchAnnouncementCard(onOpen: {}, onDismiss: {})
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Announcement Field Mode") {
    AstronomerLaunchAnnouncementCard(onOpen: {}, onDismiss: {})
        .padding()
        .appAppearance(fieldModeEnabled: true)
}
