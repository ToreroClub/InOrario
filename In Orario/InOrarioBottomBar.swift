import SwiftUI

// MARK: - Shared Semantic Visual System

enum SemanticStatusKind: Equatable {
    case regular
    case warning
    case disrupted
    case neutral

    var tint: Color {
        switch self {
        case .regular: return .green
        case .warning: return .orange
        case .disrupted: return .red
        case .neutral: return .secondary
        }
    }

    var systemImage: String {
        switch self {
        case .regular: return "checkmark.circle.fill"
        case .warning: return "clock.badge.exclamationmark.fill"
        case .disrupted: return "exclamationmark.triangle.fill"
        case .neutral: return "circle.dotted"
        }
    }
}

struct StatusBadgePill: View {
    let text: String
    let kind: SemanticStatusKind
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 4 : 5) {
            Image(systemName: kind.systemImage)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
            Text(text)
                .font(.system(size: compact ? 11 : 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(kind.tint)
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.vertical, compact ? 3.5 : 4.5)
        .background(
            Capsule(style: .continuous)
                .fill(kind.tint.opacity(0.13))
        )
    }
}

/// Shows live delay or cancellation status strictly when a train is currently traveling or cancelled.
/// When the train has not departed yet or has already arrived (and is not cancelled), renders nothing.
struct TrainLiveDelayPill: View {
    let snapshot: TrainLiveSnapshot?
    var compact: Bool = true

    private var activeBadge: (text: String, kind: SemanticStatusKind)? {
        guard let snapshot else { return nil }
        if snapshot.isCancelled {
            return ("Soppresso", .disrupted)
        }
        guard snapshot.isDeparted && !snapshot.isArrived && !snapshot.stops.isEmpty else {
            return nil
        }
        if snapshot.delayMinutes >= 15 {
            return ("+\(snapshot.delayMinutes)'", .disrupted)
        }
        if snapshot.delayMinutes > 0 {
            return ("+\(snapshot.delayMinutes)'", .warning)
        }
        if snapshot.delayMinutes < 0 {
            return ("-\(abs(snapshot.delayMinutes))'", .regular)
        }
        return ("In orario", .regular)
    }

    var body: some View {
        if let badge = activeBadge {
            Text(badge.text)
                .font(.system(size: compact ? 11 : 12, weight: .bold))
                .foregroundColor(badge.kind.tint)
                .padding(.horizontal, compact ? 7 : 8)
                .padding(.vertical, compact ? 3 : 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(badge.kind.tint.opacity(0.14))
                )
        }
    }
}

struct TrainCategoryBadge: View {
    let category: String
    var compact: Bool = false

    private var normalized: String {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? "TRN" : trimmed
    }

    private var badgeColor: Color {
        switch normalized {
        case "FR", "FA", "FB", "AV", "ES", "FRECCIAROSSA", "FRECCIARGENTO", "FRECCIABIANCA", "ITA", "ITALO", "NTV":
            return .red
        case "IC", "ICN", "EC", "EN":
            return .gray
        case "RV", "RE", "REG", "R":
            return .blue
        case "MXP", "XP":
            return Color(red: 0.65, green: 0.10, blue: 0.18)
        default:
            if let suburban = SuburbanData.shared.allLines.first(where: { $0.id.uppercased() == normalized }) {
                return suburban.color
            }
            if normalized.hasPrefix("S") {
                return .green
            }
            return .secondary
        }
    }

    var body: some View {
        Text(normalized)
            .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, compact ? 6 : 7)
            .padding(.vertical, compact ? 2.5 : 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(badgeColor)
            )
            .fixedSize()
    }
}

struct SectionCardHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var tint: Color = .accentColor
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        tint: Color = .accentColor,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)
            trailing()
        }
    }
}

struct InOrarioEmptyStateCard: View {
    let systemImage: String
    let tint: Color
    let title: String
    let message: String
    let primaryActionTitle: String
    let primaryActionIcon: String
    let onPrimaryAction: () -> Void
    var secondaryActionTitle: String? = nil
    var secondaryActionIcon: String? = nil
    var onSecondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .semibold))
                .foregroundColor(tint)
                .padding(.top, 4)

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                Button(action: onPrimaryAction) {
                    HStack(spacing: 6) {
                        Image(systemName: primaryActionIcon)
                            .font(.subheadline.weight(.semibold))
                        Text(primaryActionTitle)
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)

                if let secondaryActionTitle, let onSecondaryAction {
                    Button(action: onSecondaryAction) {
                        HStack(spacing: 6) {
                            Image(systemName: secondaryActionIcon ?? "plus")
                                .font(.subheadline.weight(.medium))
                            Text(secondaryActionTitle)
                                .font(.subheadline.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Native iOS 26 Toolbar (Matching Original Liquid Glass Grouping)

struct InOrarioTabToolbar<ExtraTrailing: View>: ToolbarContent {
    let tab: MainTab
    let hasUrgentNews: Bool
    let isMetroBetaEnabled: Bool
    @Binding var isMetroModeActive: Bool
    let onSearch: () -> Void
    let onOpenAssistant: () -> Void
    let onOpenHistory: () -> Void
    let onOpenNotifications: () -> Void
    let onOpenNews: () -> Void
    let onOpenProfile: () -> Void
    var onOpenCustomizeHome: (() -> Void)? = nil
    var hasExtraTrailing: Bool = false
    @ViewBuilder var extraTrailing: () -> ExtraTrailing

    init(
        tab: MainTab,
        hasUrgentNews: Bool,
        isMetroBetaEnabled: Bool,
        isMetroModeActive: Binding<Bool>,
        onSearch: @escaping () -> Void,
        onOpenAssistant: @escaping () -> Void,
        onOpenHistory: @escaping () -> Void,
        onOpenNotifications: @escaping () -> Void,
        onOpenNews: @escaping () -> Void,
        onOpenProfile: @escaping () -> Void,
        onOpenCustomizeHome: (() -> Void)? = nil,
        hasExtraTrailing: Bool = false,
        @ViewBuilder extraTrailing: @escaping () -> ExtraTrailing = { EmptyView() }
    ) {
        self.tab = tab
        self.hasUrgentNews = hasUrgentNews
        self.isMetroBetaEnabled = isMetroBetaEnabled
        self._isMetroModeActive = isMetroModeActive
        self.onSearch = onSearch
        self.onOpenAssistant = onOpenAssistant
        self.onOpenHistory = onOpenHistory
        self.onOpenNotifications = onOpenNotifications
        self.onOpenNews = onOpenNews
        self.onOpenProfile = onOpenProfile
        self.onOpenCustomizeHome = onOpenCustomizeHome
        self.hasExtraTrailing = hasExtraTrailing
        self.extraTrailing = extraTrailing
    }

    var body: some ToolbarContent {
        // Leading: full menu only on Home; dedicated tabs show Notifications bell only
        ToolbarItem(placement: .topBarLeading) {
            if tab == .home {
                Menu {
                    if isMetroBetaEnabled || isMetroModeActive {
                        Button {
                            Haptics.play(.medium)
                            withAnimation {
                                isMetroModeActive.toggle()
                            }
                        } label: {
                            if isMetroModeActive {
                                Label("Treni", systemImage: "tram.fill")
                            } else {
                                Label("Metropolitana", systemImage: "tram.fill")
                            }
                        }
                    }

                    if let onOpenCustomizeHome {
                        Button(action: onOpenCustomizeHome) {
                            Label("Personalizza Home", systemImage: "slider.horizontal.3")
                        }
                    }

                    Button(action: onOpenProfile) {
                        Label("Impostazioni", systemImage: "gearshape")
                    }

                    Button(action: onOpenNotifications) {
                        Label("Notifiche", systemImage: "bell.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .accessibilityLabel("Menu")
            } else {
                Button(action: onOpenNotifications) {
                    Image(systemName: "bell")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .accessibilityLabel("Notifiche")
            }
        }

        // Trailing Bubble 1: Standalone News pill
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Haptics.play(.medium)
                onOpenNews()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "newspaper.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("News")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(hasUrgentNews ? .red : .primary)
            }
        }

        if #available(iOS 26, *) {
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }

        if hasExtraTrailing {
            ToolbarItem(placement: .topBarTrailing) {
                extraTrailing()
            }

            if #available(iOS 26, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
        }

        // Trailing Bubble 2: History + Magnifying Glass together in the same Liquid Glass group
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button(action: onOpenHistory) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .accessibilityLabel("Cronologia")

            Menu {
                Button {
                    Haptics.play(.light)
                    onSearch()
                } label: {
                    Label("Cerca", systemImage: "magnifyingglass")
                }

                if !isMetroModeActive {
                    Button {
                        Haptics.play(.medium)
                        onOpenAssistant()
                    } label: {
                        Label("Chiedi all'Assistente", systemImage: "sparkles")
                    }
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
            } primaryAction: {
                Haptics.play(.medium)
                onSearch()
            }
            .accessibilityLabel("Cerca")
        }
    }
}
