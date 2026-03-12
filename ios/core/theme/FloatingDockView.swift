import SwiftUI

/// Tab identifiers for the floating dock.
enum DockTab: String, CaseIterable, Identifiable {
    case home
    case journal
    case reminders
    case caregivers
    case setup
    #if DEBUG
    case session
    #endif

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "circle.dotted"
        case .journal: return "book"
        case .reminders: return "bell"
        case .caregivers: return "person.2"
        case .setup: return "gearshape"
        #if DEBUG
        case .session: return "waveform"
        #endif
        }
    }

    var label: String {
        switch self {
        case .home: return "Home"
        case .journal: return "Journal"
        case .reminders: return "Reminders"
        case .caregivers: return "Caregivers"
        case .setup: return "Setup"
        #if DEBUG
        case .session: return "Session"
        #endif
        }
    }
}

/// Frosted white floating pill dock.
/// Colored icon + dot for selected tab, muted icons for unselected.
struct FloatingDockView: View {
    @Binding var selectedTab: DockTab
    let visibleTabs: [DockTab]

    private let pillHeight: CGFloat = 56
    private let minIconTouchSize: CGFloat = 60
    private let selectedColor = Color(hex: "#4A54E1")

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20, weight: isSelected ? .semibold : .medium))
                            .foregroundColor(isSelected ? selectedColor : Color(hex: "#1E293B").opacity(0.35))

                        Circle()
                            .fill(isSelected ? selectedColor : .clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42)
                    .contentShape(Rectangle())
                    .frame(minWidth: minIconTouchSize, minHeight: minIconTouchSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .frame(height: pillHeight)
        .background(
            Capsule()
                .fill(.white)
                .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                )
        )
    }
}
