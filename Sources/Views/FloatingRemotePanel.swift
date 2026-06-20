import SwiftUI

/// Floating Now Playing / Library switcher — liquid-glass capsule pinned above
/// navigation content (including library folder pushes).
struct FloatingRemotePanel: View {
    @Binding var selectedTab: Int

    var body: some View {
        HStack(spacing: 4) {
            tabButton(title: "Now Playing", systemImage: "play.circle", tag: 0)
            tabButton(title: "Library", systemImage: "music.note.list", tag: 1)
        }
        .padding(4)
        .background { liquidGlassCapsule }
        .shadow(color: .black.opacity(0.14), radius: 24, y: 10)
    }

    private var liquidGlassCapsule: some View {
        ZStack {
            Capsule()
                .fill(.ultraThinMaterial)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.28),
                            Color.white.opacity(0.06),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.overlay)

            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.25),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
        }
    }

    private func tabButton(title: String, systemImage: String, tag: Int) -> some View {
        Button {
            if selectedTab != tag { Haptics.selection() }
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tag
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .foregroundStyle(selectedTab == tag ? Color.white : Color.primary)
            .background {
                if selectedTab == tag {
                    Capsule()
                        .fill(Color.accentColor)
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 8, y: 3)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedTab == tag ? .isSelected : [])
    }
}
