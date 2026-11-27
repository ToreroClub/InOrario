import SwiftUI

// MARK: - Lines Tab Root View

struct LinesTabRootView: View {
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var usageTracker: UsageTracker
    @EnvironmentObject var personalLinesManager: PersonalLinesManager
    @EnvironmentObject var navigationCoordinator: MainNavigationCoordinator

    let news: [NewsItem]
    let isActiveTab: Bool
    let onOpenNotifications: () -> Void

    @AppStorage("linesSectionExpandedIDs_v1") private var storedExpandedLineIDsRaw: String = ""
    @AppStorage("linesSuggestedExpanded_v1") private var isSuggestedLinesExpanded: Bool = false

    @State private var isEditingOrder: Bool = false
    @State private var expandedLineIDs: Set<String> = []
    @State private var hasHydratedExpandedLines: Bool = false
    @State private var showManageLinesSheet: Bool = false
    @State private var showPassanteDetailSheet: Bool = false
    @State private var selectedDetailLine: PersonalRailwayLine? = nil
    @State private var selectedLineStation: Station? = nil
    @State private var previewSuggestedLine: PersonalRailwayLine? = nil

    private func hydrateExpandedLineIDsIfNeeded() {
        guard !hasHydratedExpandedLines else { return }
        hasHydratedExpandedLines = true
        let parsed = storedExpandedLineIDsRaw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        expandedLineIDs = Set(parsed)
    }

    private func persistExpandedLineIDs(_ ids: Set<String>) {
        storedExpandedLineIDsRaw = ids.sorted().joined(separator: ",")
    }

    var body: some View {
        List {
            if personalLinesManager.savedLines.isEmpty && personalLinesManager.suggestedLines.isEmpty {
                Section {
                    InOrarioEmptyStateCard(
                        systemImage: "point.topleft.down.curvedto.point.bottomright.up.fill",
                        tint: .green,
                        title: "Nessuna linea configurata",
                        message: "Aggiungi le tue linee suburbane, regionali o Alta Velocità per avere sempre a portata di mano fermate, prossime partenze e lavori RFI.",
                        primaryActionTitle: "Aggiungi linee",
                        primaryActionIcon: "plus.circle.fill",
                        onPrimaryAction: {
                            showManageLinesSheet = true
                        }
                    )
                }
            } else {
                if !personalLinesManager.savedLines.isEmpty {
                    if isEditingOrder {
                        Section {
                            ForEach(personalLinesManager.savedLines) { line in
                                ExpandableLineRowView(
                                    line: line,
                                    isExpanded: false,
                                    relevantNewsCount: personalLinesManager.relevantNews(for: line, from: news).count,
                                    showDetailButtonInExpanded: false,
                                    isReorderMode: true,
                                    onPrimaryTap: {},
                                    onToggleExpand: {},
                                    onOpenDetail: {},
                                    onOpenPassanteDetail: nil,
                                    onSelectStation: nil
                                )
                                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        Haptics.play(.light)
                                        withAnimation {
                                            expandedLineIDs.remove(line.id)
                                            personalLinesManager.removeLine(id: line.id, passanteManager: passanteManager)
                                        }
                                    } label: {
                                        Label("Rimuovi dai preferiti", systemImage: "star.slash.fill")
                                    }
                                }
                            }
                            .onMove { source, destination in
                                Haptics.play(.light)
                                personalLinesManager.moveSavedLines(from: source, to: destination)
                            }
                        } header: {
                            Text("Le mie linee")
                        } footer: {
                            Text("Tieni premuto e trascina per riordinare. Scorri verso sinistra per rimuovere una linea dai preferiti.")
                        }
                    } else {
                        ForEach(Array(personalLinesManager.savedLines.enumerated()), id: \.element.id) { index, line in
                            Section {
                                ExpandableLineRowView(
                                    line: line,
                                    isExpanded: expandedLineIDs.contains(line.id),
                                    relevantNewsCount: personalLinesManager.relevantNews(for: line, from: news).count,
                                    showDetailButtonInExpanded: false,
                                    isReorderMode: false,
                                    onPrimaryTap: {
                                        selectedDetailLine = line
                                    },
                                    onToggleExpand: {
                                        Haptics.play(.light)
                                        if expandedLineIDs.contains(line.id) {
                                            expandedLineIDs.remove(line.id)
                                        } else {
                                            expandedLineIDs.insert(line.id)
                                            UserInterestTelemetryManager.shared.recordLineView(
                                                lineID: line.id,
                                                code: line.code,
                                                name: line.name,
                                                kind: line.kind.rawValue,
                                                region: line.effectiveRegion
                                            )
                                        }
                                    },
                                    onOpenDetail: {
                                        selectedDetailLine = line
                                    },
                                    onOpenPassanteDetail: {
                                        showPassanteDetailSheet = true
                                    },
                                    onSelectStation: { station in
                                        selectedLineStation = station
                                    }
                                )
                                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        Haptics.play(.light)
                                        withAnimation {
                                            expandedLineIDs.remove(line.id)
                                            personalLinesManager.removeLine(id: line.id, passanteManager: passanteManager)
                                        }
                                    } label: {
                                        Label("Rimuovi dai preferiti", systemImage: "star.slash.fill")
                                    }
                                }
                            } header: {
                                if index == 0 {
                                    Text("Le mie linee")
                                }
                            }
                        }
                    }
                }

                if !personalLinesManager.suggestedLines.isEmpty && !isEditingOrder {
                    Section {
                        if isSuggestedLinesExpanded {
                            ForEach(personalLinesManager.suggestedLines) { suggestion in
                                HStack(spacing: 10) {
                                    Button {
                                        Haptics.play(.light)
                                        previewSuggestedLine = suggestion.line
                                    } label: {
                                        HStack(spacing: 10) {
                                            LineCodeBadge(line: suggestion.line)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(suggestion.line.name)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundColor(.primary)
                                                    .lineLimit(1)
                                                Text(suggestion.reason)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        Haptics.notify(.success)
                                        withAnimation {
                                            personalLinesManager.addLine(suggestion.line, passanteManager: passanteManager)
                                        }
                                    } label: {
                                        Image(systemName: "star")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(.yellow)
                                    }
                                    .buttonStyle(.plain)
                                    .fixedSize()
                                    .accessibilityLabel("Aggiungi linea ai preferiti")
                                }
                                .padding(.vertical, 3)
                                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        Haptics.notify(.success)
                                        withAnimation {
                                            personalLinesManager.addLine(suggestion.line, passanteManager: passanteManager)
                                        }
                                    } label: {
                                        Label("Preferito", systemImage: "star.fill")
                                    }
                                    .tint(.yellow)
                                }
                            }
                        }
                    } header: {
                        Button {
                            Haptics.play(.light)
                            withAnimation(.snappy(duration: 0.25)) {
                                isSuggestedLinesExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("Suggerite per te")
                                Spacer()
                                Image(systemName: isSuggestedLinesExpanded ? "chevron.down" : "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.custom(12))
        .navigationTitle("Linee")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $selectedDetailLine) { line in
            RailwayLineDetailView(line: line, news: news)
        }
        .navigationDestination(item: $selectedLineStation) { station in
            SmartBoardView(station: station)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onOpenNotifications) {
                    Image(systemName: "bell")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .accessibilityLabel("Notifiche")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.play(.light)
                    withAnimation { isEditingOrder.toggle() }
                } label: {
                    Image(systemName: isEditingOrder ? "checkmark" : "arrow.up.arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isEditingOrder ? .green : (personalLinesManager.savedLines.count > 1 ? .primary : .secondary))
                }
                .disabled(personalLinesManager.savedLines.count <= 1 && !isEditingOrder)
                .accessibilityLabel(isEditingOrder ? "Fine riordino" : "Riordina linee")
            }

            if #available(iOS 26, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.play(.light)
                    showManageLinesSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .accessibilityLabel("Aggiungi linee")
            }
        }
        // Lightweight Passante health dot check ONLY when Lines tab is active (4 min cache); everything else stays frozen until expanded/opened
        .task(id: "\(isActiveTab)|\(passanteManager.userUsesTunnel)") {
            guard isActiveTab, passanteManager.userUsesTunnel else { return }
            _ = await passanteManager.refreshTunnelHealthIfNeeded(manager: manager, minInterval: 240)
        }
        .refreshable {
            if passanteManager.userUsesTunnel {
                _ = await passanteManager.refreshTunnelHealthIfNeeded(manager: manager, minInterval: 0, force: true)
            }
            await refreshExpandedLinesOnly(force: true)
        }
        .onAppear {
            hydrateExpandedLineIDsIfNeeded()
            consumePendingLineDeepLink()
        }
        .onChange(of: expandedLineIDs) { _, newIDs in
            guard hasHydratedExpandedLines else { return }
            persistExpandedLineIDs(newIDs)
        }
        .onChange(of: navigationCoordinator.pendingLineIDToOpen) { _, _ in
            consumePendingLineDeepLink()
        }
        .sheet(isPresented: $showManageLinesSheet) {
            LineManagementSheet(news: news)
                .environmentObject(manager)
                .environmentObject(passanteManager)
                .environmentObject(locationManager)
                .environmentObject(personalLinesManager)
        }
        .sheet(item: $previewSuggestedLine) { line in
            NavigationStack {
                LineCatalogPreviewView(line: line, news: news, isSheet: true)
                    .environmentObject(manager)
                    .environmentObject(passanteManager)
                    .environmentObject(locationManager)
                    .environmentObject(personalLinesManager)
            }
        }
        .sheet(isPresented: $showPassanteDetailSheet) {
            PassanteTunnelDetailView()
                .environmentObject(manager)
                .environmentObject(passanteManager)
        }
    }

    private func consumePendingLineDeepLink() {
        guard let lineID = navigationCoordinator.pendingLineIDToOpen else { return }
        if let match = personalLinesManager.savedLines.first(where: { $0.id == lineID })
            ?? RailwayLineCatalog.curatedCatalog.first(where: { $0.id == lineID }) {
            selectedDetailLine = match
        }
        navigationCoordinator.pendingLineIDToOpen = nil
    }

    private func refreshExpandedLinesOnly(force: Bool) async {
        let expanded = personalLinesManager.savedLines.filter { expandedLineIDs.contains($0.id) }
        guard !expanded.isEmpty else { return }
        let activeNearby = locationManager.manualNearbyStation ?? locationManager.nearbyStation
        for line in expanded {
            let visible = personalLinesManager.visibleResolvedStations(
                for: line,
                trainManager: manager,
                passanteManager: passanteManager
            )
            if let station = personalLinesManager.nearestStation(
                on: line,
                visibleStations: visible,
                activeNearby: activeNearby,
                userLocation: locationManager.userLocation
            ) {
                await personalLinesManager.refreshNearbyDepartures(
                    for: line,
                    station: station,
                    visibleStations: visible,
                    trainManager: manager,
                    passanteManager: passanteManager,
                    force: force
                )
            }
        }
    }
}

// MARK: - Line Code Badge

struct LineCodeBadge: View {
    let line: PersonalRailwayLine
    var compact: Bool = false

    var body: some View {
        Text(line.code)
            .font(.system(size: compact ? 11 : 12, weight: .bold, design: .rounded))
            .foregroundColor(line.badgeTextColor)
            .padding(.horizontal, compact ? 7 : 8)
            .padding(.vertical, compact ? 4 : 5)
            .background(line.color)
            .clipShape(RoundedRectangle(cornerRadius: compact ? 6 : 8, style: .continuous))
    }
}

// MARK: - Shared Expandable Line Row (Home & Lines Tab)

enum ExpandedLineDisplayMode: Equatable {
    case nearbyOnly
    case compactWindow(maxStations: Int)
}

struct ExpandableLineRowView: View {
    let line: PersonalRailwayLine
    let isExpanded: Bool
    let relevantNewsCount: Int
    var expandedDisplayMode: ExpandedLineDisplayMode = .compactWindow(maxStations: 5)
    var showDetailButtonInExpanded: Bool = false
    var isReorderMode: Bool = false
    let onPrimaryTap: () -> Void
    let onToggleExpand: () -> Void
    let onOpenDetail: () -> Void
    var onOpenPassanteDetail: (() -> Void)? = nil
    var onSelectStation: ((Station) -> Void)? = nil

    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var personalLinesManager: PersonalLinesManager

    private var visibleStations: [Station] {
        personalLinesManager.visibleResolvedStations(
            for: line,
            trainManager: manager,
            passanteManager: passanteManager
        )
    }

    private var activeNearby: Station? {
        personalLinesManager.nearestStation(
            on: line,
            visibleStations: visibleStations,
            activeNearby: locationManager.manualNearbyStation ?? locationManager.nearbyStation,
            userLocation: locationManager.userLocation
        )
    }

    private var nearbyInfo: LineNearbyDepartures? {
        guard let station = activeNearby else { return nil }
        let key = TrainManager.canonicalStationKey(for: station)
        guard let cached = personalLinesManager.nearbyDeparturesByLine[line.id],
              cached.stationKey == key else {
            return nil
        }
        return cached
    }

    private var isLoadingNearby: Bool {
        personalLinesManager.loadingNearbyLineIDs.contains(line.id)
    }

    private var fetchTaskKey: String {
        guard isExpanded else { return "collapsed" }
        let stationKey = activeNearby.map { TrainManager.canonicalStationKey(for: $0) } ?? "none"
        return "\(line.id)|\(stationKey)"
    }

    private var passanteDotColor: Color {
        Color(hex: passanteManager.passanteTunnelHealthColor)
    }

    private var passanteCompactLabel: String {
        let msg = passanteManager.passanteTunnelHealthMessage
        return msg.isEmpty ? "Passante Ferroviario" : msg
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: onPrimaryTap) {
                    HStack(spacing: 10) {
                        LineCodeBadge(line: line, compact: true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            HStack(spacing: 6) {
                                if line.usesPassanteTunnel {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(passanteDotColor)
                                            .frame(width: 7, height: 7)
                                        Text(passanteCompactLabel)
                                            .font(.caption.weight(.medium))
                                            .foregroundColor(passanteDotColor)
                                            .lineLimit(1)
                                    }
                                } else {
                                    Text(line.kind.rawValue)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                if relevantNewsCount > 0 {
                                    Text("· \(relevantNewsCount) avvis\(relevantNewsCount == 1 ? "o" : "i")")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.orange)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(isReorderMode)

                if isReorderMode {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .accessibilityLabel("Trascina per riordinare")
                } else {
                    Button(action: onToggleExpand) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .fixedSize()
                    .accessibilityLabel(isExpanded ? "Comprimi linea" : "Espandi linea")
                }
            }

            if isExpanded && !isReorderMode {
                Divider()

                if line.usesPassanteTunnel, let onOpenPassanteDetail {
                    Button {
                        Haptics.play(.light)
                        onOpenPassanteDetail()
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(passanteDotColor)
                                .frame(width: 8, height: 8)
                            Text("Stato galleria")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(passanteDotColor)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(passanteDotColor.opacity(0.85))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(passanteDotColor.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.borderless)
                }

                switch expandedDisplayMode {
                case .nearbyOnly:
                    homeNearbyDeparturesBlock
                case .compactWindow(let maxStations):
                    VerticalRailwayLineDiagramView(
                        line: line,
                        visibleStations: visibleStations,
                        nearbyStation: activeNearby,
                        directionBadges: nearbyInfo?.directionBadges,
                        isLoadingNearby: isLoadingNearby,
                        showsNearbyDepartures: true,
                        maxVisibleStations: maxStations,
                        onSelectStation: onSelectStation,
                        onSelectManualStation: { station in
                            selectManualStation(station)
                        },
                        onOpenFullLine: onOpenDetail
                    )
                }

                if showDetailButtonInExpanded {
                    HStack {
                        Spacer()

                        Button(action: onOpenDetail) {
                            HStack(spacing: 4) {
                                Text("Scheda linea")
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.borderless)
                        .fixedSize()
                    }
                }
            }
        }
        .padding(.vertical, 3)
        // Strictly lazy: ZERO station board requests while collapsed
        .task(id: fetchTaskKey) {
            guard isExpanded, let station = activeNearby else { return }
            await personalLinesManager.refreshNearbyDepartures(
                for: line,
                station: station,
                visibleStations: visibleStations,
                trainManager: manager,
                passanteManager: passanteManager,
                force: false
            )
        }
    }

    private var trackHighlightColor: Color {
        PersonalRailwayLine.isLightHexColor(line.hexColor) ? .orange : line.color
    }

    @ViewBuilder
    private var homeNearbyDeparturesBlock: some View {
        if let nearby = activeNearby {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    Haptics.play(.light)
                    onSelectStation?(nearby)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(trackHighlightColor)
                        Text(nearby.formattedName.compactStationName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)

                if let departures = nearbyInfo?.departures, !departures.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(departures.prefix(3))) { train in
                            let isCancelled = train.delay.localizedCaseInsensitiveContains("soppresso")
                                || train.delay.localizedCaseInsensitiveContains("cancellat")
                            let delayMins = TrainManager.parseDelayMinutes(from: train.delay) ?? 0
                            let delayColor: Color = {
                                if isCancelled || delayMins >= 15 { return .red }
                                if delayMins > 0 { return .orange }
                                return .green
                            }()
                            let delayLabel = isCancelled ? "Soppresso" : (train.delay.isEmpty ? "In orario" : train.delay)

                            HStack(spacing: 8) {
                                Text(train.time)
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundColor(.primary)
                                Text(train.destination.compactStationName)
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                if !train.platform.isEmpty && train.platform != "--" {
                                    Text("Bin. \(train.platform)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Text(delayLabel)
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundColor(delayColor)
                            }
                        }
                    }
                } else if let badges = nearbyInfo?.directionBadges, !badges.isEmpty {
                    Text(badges.joined(separator: "  ·  "))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundColor(.blue)
                        .lineLimit(1)
                } else if isLoadingNearby {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Aggiornamento partenze...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Nessuna partenza imminente")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 2)
        } else {
            Text("Nessuna fermata della linea rilevata nelle vicinanze")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.vertical, 2)
        }
    }

    private func selectManualStation(_ station: Station) {
        Haptics.play(.heavy)
        locationManager.manualNearbyStation = station
        if line.usesPassanteTunnel {
            passanteManager.selectPassanteStation(station, manager: manager)
        }
        Task {
            await personalLinesManager.refreshNearbyDepartures(
                for: line,
                station: station,
                visibleStations: visibleStations,
                trainManager: manager,
                passanteManager: passanteManager,
                force: true
            )
        }
    }
}

// MARK: - Vertical Railway Line Diagram with Y-Forks & Hardcoded Interchanges

private enum VerticalDiagramItem: Identifiable {
    case branchHeader(
        id: String,
        label: String,
        isDashed: Bool,
        isBeforeBranch: Bool,
        hasMainThrough: Bool
    )
    case station(
        id: String,
        station: Station,
        column: Int, // 0 = trunk, 1 = side branch
        hasTopMain: Bool,
        hasBottomMain: Bool,
        hasTopBranch: Bool,
        hasBottomBranch: Bool,
        branchIsDashed: Bool,
        mainIsDashed: Bool,
        mergeFromBranchAtTop: Bool
    )

    var id: String {
        switch self {
        case .branchHeader(let id, _, _, _, _): return id
        case .station(let id, _, _, _, _, _, _, _, _, _): return id
        }
    }
}

private enum VerticalDiagramBuilder {
    static func build(line: PersonalRailwayLine, visibleStations: [Station]) -> [VerticalDiagramItem] {
        guard !visibleStations.isEmpty else { return [] }

        let branches = line.branches ?? []
        if branches.isEmpty {
            return visibleStations.enumerated().map { idx, st in
                .station(
                    id: "st_\(idx)_\(st.name)",
                    station: st,
                    column: 0,
                    hasTopMain: idx > 0,
                    hasBottomMain: idx < visibleStations.count - 1,
                    hasTopBranch: false,
                    hasBottomBranch: false,
                    branchIsDashed: false,
                    mainIsDashed: false,
                    mergeFromBranchAtTop: false
                )
            }
        }

        func resolveVisible(_ rawName: String) -> Station? {
            visibleStations.first {
                RailwayLineCatalog.stationsLikelyMatch($0.name, rawName)
                || RailwayLineCatalog.stationsLikelyMatch($0.formattedName, rawName)
            }
        }

        var branchStationTokens = Set<String>()
        for b in branches {
            for s in b.stations {
                branchStationTokens.insert(RailwayLineCatalog.normalizeStationToken(s))
            }
        }

        let trunkStations = visibleStations.filter { st in
            let t1 = RailwayLineCatalog.normalizeStationToken(st.name)
            let t2 = RailwayLineCatalog.normalizeStationToken(st.formattedName)
            return !branchStationTokens.contains(t1) && !branchStationTokens.contains(t2)
        }

        var items: [VerticalDiagramItem] = []

        for trunkIdx in trunkStations.indices {
            let trunkStation = trunkStations[trunkIdx]
            let hasMainBefore = trunkIdx > 0
            let hasMainAfter = trunkIdx < trunkStations.count - 1

            let beforeBranches = branches.filter {
                $0.effectivePosition == .before
                && (RailwayLineCatalog.stationsLikelyMatch($0.junctionStation, trunkStation.name)
                    || RailwayLineCatalog.stationsLikelyMatch($0.junctionStation, trunkStation.formattedName))
            }
            let afterBranches = branches.filter {
                $0.effectivePosition == .after
                && (RailwayLineCatalog.stationsLikelyMatch($0.junctionStation, trunkStation.name)
                    || RailwayLineCatalog.stationsLikelyMatch($0.junctionStation, trunkStation.formattedName))
            }

            let resolvedBeforeGroups: [(branch: RailwayLineBranch, stations: [Station])] = beforeBranches.compactMap { branch in
                let stList = branch.stations.compactMap(resolveVisible)
                return stList.isEmpty ? nil : (branch, stList)
            }
            let hasIncomingBranch = !resolvedBeforeGroups.isEmpty

            // 1. Render `.before` branches converging into `trunkStation`
            for (bIdx, group) in resolvedBeforeGroups.enumerated() {
                let isDashed = group.branch.effectiveIsDashed
                items.append(
                    .branchHeader(
                        id: "bh_before_\(trunkIdx)_\(bIdx)_\(group.branch.label)",
                        label: group.branch.label,
                        isDashed: isDashed,
                        isBeforeBranch: true,
                        hasMainThrough: hasMainBefore
                    )
                )
                for (sIdx, bSt) in group.stations.enumerated() {
                    items.append(
                        .station(
                            id: "br_before_\(trunkIdx)_\(bIdx)_\(sIdx)_\(bSt.name)",
                            station: bSt,
                            column: 1,
                            hasTopMain: hasMainBefore,
                            hasBottomMain: hasMainBefore,
                            hasTopBranch: sIdx > 0,
                            hasBottomBranch: true, // connects cleanly down into junction merge curve
                            branchIsDashed: isDashed,
                            mainIsDashed: false,
                            mergeFromBranchAtTop: false
                        )
                    )
                }
            }

            // 2. Render `trunkStation`
            items.append(
                .station(
                    id: "trunk_\(trunkIdx)_\(trunkStation.name)",
                    station: trunkStation,
                    column: 0,
                    hasTopMain: hasMainBefore,
                    hasBottomMain: hasMainAfter,
                    hasTopBranch: false,
                    hasBottomBranch: false,
                    branchIsDashed: resolvedBeforeGroups.last?.branch.effectiveIsDashed ?? false,
                    mainIsDashed: false,
                    mergeFromBranchAtTop: hasIncomingBranch
                )
            )

            // 3. Render `.after` branches splitting out from `trunkStation`
            let resolvedAfterGroups: [(branch: RailwayLineBranch, stations: [Station])] = afterBranches.compactMap { branch in
                let stList = branch.stations.compactMap(resolveVisible)
                return stList.isEmpty ? nil : (branch, stList)
            }
            for (bIdx, group) in resolvedAfterGroups.enumerated() {
                let isDashed = group.branch.effectiveIsDashed
                items.append(
                    .branchHeader(
                        id: "bh_after_\(trunkIdx)_\(bIdx)_\(group.branch.label)",
                        label: group.branch.label,
                        isDashed: isDashed,
                        isBeforeBranch: false,
                        hasMainThrough: hasMainAfter
                    )
                )
                for (sIdx, bSt) in group.stations.enumerated() {
                    items.append(
                        .station(
                            id: "br_after_\(trunkIdx)_\(bIdx)_\(sIdx)_\(bSt.name)",
                            station: bSt,
                            column: 1,
                            hasTopMain: hasMainAfter,
                            hasBottomMain: hasMainAfter,
                            hasTopBranch: true,
                            hasBottomBranch: sIdx < group.stations.count - 1,
                            branchIsDashed: isDashed,
                            mainIsDashed: false,
                            mergeFromBranchAtTop: false
                        )
                    )
                }
            }
        }

        return items
    }
}

struct VerticalRailwayLineDiagramView: View {
    let line: PersonalRailwayLine
    let visibleStations: [Station]
    let nearbyStation: Station?
    let directionBadges: [String]?
    let isLoadingNearby: Bool
    var showsNearbyDepartures: Bool = true
    var maxVisibleStations: Int? = nil
    var onSelectStation: ((Station) -> Void)? = nil
    var onSelectManualStation: ((Station) -> Void)? = nil
    var onOpenFullLine: (() -> Void)? = nil

    @State private var activeInterchangePopoverKey: String? = nil
    @State private var lastLongPressAt: Date = .distantPast

    private var trackHighlightColor: Color {
        PersonalRailwayLine.isLightHexColor(line.hexColor) ? .orange : line.color
    }

    private var allItems: [VerticalDiagramItem] {
        VerticalDiagramBuilder.build(line: line, visibleStations: visibleStations)
    }

    private var windowedResult: (items: [VerticalDiagramItem], totalStations: Int, isClipped: Bool) {
        let built = allItems
        let stationItemIndices = built.indices.filter {
            if case .station = built[$0] { return true }
            return false
        }
        let total = stationItemIndices.count
        guard let limit = maxVisibleStations, total > limit else {
            return (built, total, false)
        }

        let centerStationPos: Int = {
            if let near = nearbyStation,
               let matchPos = stationItemIndices.firstIndex(where: { idx in
                   if case .station(_, let st, _, _, _, _, _, _, _, _) = built[idx] {
                       return isStationNearby(station: st, activeNearby: near)
                   }
                   return false
               }) {
                return matchPos
            }
            return 0
        }()

        let half = limit / 2
        var startPos = max(0, centerStationPos - half)
        let endPos = min(total, startPos + limit)
        startPos = max(0, endPos - limit)

        var sliceStart = stationItemIndices[startPos]
        let sliceEnd = stationItemIndices[endPos - 1]
        if sliceStart > 0, case .branchHeader = built[sliceStart - 1] {
            sliceStart -= 1
        }
        return (Array(built[sliceStart...sliceEnd]), total, true)
    }

    private func rowHeight(for station: Station) -> CGFloat {
        let isNear = isStationNearby(station: station, activeNearby: nearbyStation)
        let showsDepartures = isNear && showsNearbyDepartures
        if showsDepartures {
            return 62
        }
        let hasInterchanges = !StationInterchangeCatalog.interchanges(
            for: station.formattedName,
            excludingLineCode: line.code
        ).isEmpty
        return hasInterchanges ? 60 : 50
    }

    var body: some View {
        let window = windowedResult
        VStack(alignment: .leading, spacing: 0) {
            diagramRowsStack(window.items)

            if window.isClipped, let onOpenFullLine {
                Divider()
                    .padding(.vertical, 6)

                Button {
                    Haptics.play(.light)
                    onOpenFullLine()
                } label: {
                    HStack(spacing: 6) {
                        Text("Vedi tutta la linea (\(window.totalStations) fermate)")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.accentColor)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func diagramRowsStack(_ rows: [VerticalDiagramItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { item in
                switch item {
                case .branchHeader(_, let label, let isDashed, let isBeforeBranch, let hasMainThrough):
                    branchHeaderRow(
                        label: label,
                        isDashed: isDashed,
                        isBeforeBranch: isBeforeBranch,
                        hasMainThrough: hasMainThrough
                    )
                case .station(
                    _,
                    let station,
                    let column,
                    let hasTopMain,
                    let hasBottomMain,
                    let hasTopBranch,
                    let hasBottomBranch,
                    let branchIsDashed,
                    let mainIsDashed,
                    let mergeFromBranchAtTop
                ):
                    stationRow(
                        station: station,
                        column: column,
                        hasTopMain: hasTopMain,
                        hasBottomMain: hasBottomMain,
                        hasTopBranch: hasTopBranch,
                        hasBottomBranch: hasBottomBranch,
                        branchIsDashed: branchIsDashed,
                        mainIsDashed: mainIsDashed,
                        mergeFromBranchAtTop: mergeFromBranchAtTop
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func branchHeaderRow(
        label: String,
        isDashed: Bool,
        isBeforeBranch: Bool,
        hasMainThrough: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Canvas { context, size in
                let mainX: CGFloat = 12
                let branchX: CGFloat = 30
                let strokeColor = line.color.opacity(0.75)
                let solidStyle = StrokeStyle(lineWidth: 3.5, lineCap: .round)
                let dashStyle = StrokeStyle(lineWidth: 3.0, lineCap: .round, dash: [4, 3])
                let branchStyle = isDashed ? dashStyle : solidStyle

                if hasMainThrough {
                    var p = Path()
                    p.move(to: CGPoint(x: mainX, y: 0))
                    p.addLine(to: CGPoint(x: mainX, y: size.height))
                    context.stroke(p, with: .color(strokeColor), style: solidStyle)
                }

                if !isBeforeBranch {
                    // Split S-curve from trunk (mainX, 0) out to branch (branchX, size.height)
                    var fork = Path()
                    fork.move(to: CGPoint(x: mainX, y: 0))
                    fork.addCurve(
                        to: CGPoint(x: branchX, y: size.height),
                        control1: CGPoint(x: mainX, y: size.height * 0.55),
                        control2: CGPoint(x: branchX, y: size.height * 0.45)
                    )
                    context.stroke(fork, with: .color(strokeColor), style: branchStyle)
                }
            }
            .frame(width: 44, height: 28)

            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundColor(trackHighlightColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(line.color.opacity(0.12))
                .clipShape(Capsule())

            Spacer()
        }
        .frame(height: 28)
    }

    private func stationRow(
        station: Station,
        column: Int,
        hasTopMain: Bool,
        hasBottomMain: Bool,
        hasTopBranch: Bool,
        hasBottomBranch: Bool,
        branchIsDashed: Bool,
        mainIsDashed: Bool,
        mergeFromBranchAtTop: Bool
    ) -> some View {
        let isNear = isStationNearby(station: station, activeNearby: nearbyStation)
        let showsDepartures = isNear && showsNearbyDepartures
        let interchanges = StationInterchangeCatalog.interchanges(
            for: station.formattedName,
            excludingLineCode: line.code
        )
        let computedHeight = rowHeight(for: station)
        let stationPopoverKey = TrainManager.canonicalStationKey(for: station)

        return HStack(spacing: 8) {
            Button {
                guard Date().timeIntervalSince(lastLongPressAt) > 0.6 else { return }
                Haptics.play(.light)
                onSelectStation?(station)
            } label: {
                HStack(spacing: 8) {
                    Canvas { context, size in
                        let mainX: CGFloat = 12
                        let branchX: CGFloat = 30
                        let midY = size.height * 0.5
                        let nodeX = column == 0 ? mainX : branchX
                        let trackOpacity = line.color.opacity(0.75)

                        let solidStyle = StrokeStyle(lineWidth: 3.5, lineCap: .round)
                        let dashStyle = StrokeStyle(lineWidth: 3.0, lineCap: .round, dash: [4, 3])
                        let mainStyle = mainIsDashed ? dashStyle : solidStyle
                        let bStyle = branchIsDashed ? dashStyle : solidStyle

                        if hasTopMain {
                            var p = Path()
                            p.move(to: CGPoint(x: mainX, y: 0))
                            p.addLine(to: CGPoint(x: mainX, y: column == 0 ? midY : size.height))
                            context.stroke(p, with: .color(trackOpacity), style: mainStyle)
                        }
                        if hasBottomMain {
                            var p = Path()
                            p.move(to: CGPoint(x: mainX, y: column == 0 ? midY : 0))
                            p.addLine(to: CGPoint(x: mainX, y: size.height))
                            context.stroke(p, with: .color(trackOpacity), style: mainStyle)
                        }
                        if mergeFromBranchAtTop {
                            var merge = Path()
                            merge.move(to: CGPoint(x: branchX, y: 0))
                            merge.addCurve(
                                to: CGPoint(x: mainX, y: midY),
                                control1: CGPoint(x: branchX, y: midY * 0.55),
                                control2: CGPoint(x: mainX, y: midY * 0.45)
                            )
                            context.stroke(merge, with: .color(trackOpacity), style: bStyle)
                        }
                        if hasTopBranch {
                            var p = Path()
                            p.move(to: CGPoint(x: branchX, y: 0))
                            p.addLine(to: CGPoint(x: branchX, y: midY))
                            context.stroke(p, with: .color(trackOpacity), style: bStyle)
                        }
                        if hasBottomBranch {
                            var p = Path()
                            p.move(to: CGPoint(x: branchX, y: midY))
                            p.addLine(to: CGPoint(x: branchX, y: size.height))
                            context.stroke(p, with: .color(trackOpacity), style: bStyle)
                        }

                        // Station node dot
                        if isNear {
                            let outerRect = CGRect(x: nodeX - 7.5, y: midY - 7.5, width: 15, height: 15)
                            context.fill(Path(ellipseIn: outerRect), with: .color(line.color))
                            let innerRect = CGRect(x: nodeX - 3.5, y: midY - 3.5, width: 7, height: 7)
                            context.fill(Path(ellipseIn: innerRect), with: .color(Color(.systemBackground)))
                        } else {
                            let dotRect = CGRect(x: nodeX - 5.5, y: midY - 5.5, width: 11, height: 11)
                            context.fill(Path(ellipseIn: dotRect), with: .color(Color(.systemBackground)))
                            context.stroke(
                                Path(ellipseIn: dotRect),
                                with: .color(column == 0 ? line.color : line.color.opacity(0.85)),
                                lineWidth: 2.5
                            )
                        }
                    }
                    .frame(width: 44, height: computedHeight)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(station.formattedName.compactStationName)
                            .font(.subheadline.weight(isNear ? .bold : .medium))
                            .foregroundColor(isNear ? trackHighlightColor : .primary)
                            .lineLimit(1)

                        if showsDepartures {
                            if let badges = directionBadges, !badges.isEmpty {
                                Text(badges.joined(separator: "  ·  "))
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .foregroundColor(.blue)
                                    .lineLimit(1)
                            } else if isLoadingNearby {
                                Text("Aggiornamento partenze...")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Nessuna partenza imminente")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        } else if !interchanges.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(interchanges.prefix(5)) { badge in
                                    interchangePill(badge)
                                }
                                if interchanges.count > 5 {
                                    Text("+\(interchanges.count - 5)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color(.tertiarySystemFill))
                                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                }
                            }
                        }
                    }
                    .padding(.vertical, 5)

                    Spacer(minLength: 4)
                }
                .frame(maxWidth: .infinity, minHeight: computedHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onEnded { _ in
                        lastLongPressAt = Date()
                        onSelectManualStation?(station)
                    }
            )

            if showsDepartures && !interchanges.isEmpty {
                Button {
                    Haptics.play(.light)
                    activeInterchangePopoverKey = stationPopoverKey
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .fixedSize()
                .accessibilityLabel("Interscambi a \(station.formattedName.compactStationName)")
                .popover(
                    isPresented: Binding(
                        get: { activeInterchangePopoverKey == stationPopoverKey },
                        set: { if !$0 && activeInterchangePopoverKey == stationPopoverKey { activeInterchangePopoverKey = nil } }
                    ),
                    arrowEdge: .trailing
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Interscambi · \(station.formattedName.compactStationName)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 40), spacing: 5)],
                            alignment: .leading,
                            spacing: 5
                        ) {
                            ForEach(interchanges) { badge in
                                interchangePill(badge)
                            }
                        }
                    }
                    .padding(12)
                    .frame(minWidth: 200, maxWidth: 250, alignment: .leading)
                    .presentationCompactAdaptation(.popover)
                }
            }
        }
        .frame(minHeight: computedHeight)
    }

    private func interchangePill(_ badge: InterchangeBadge) -> some View {
        Text(badge.code)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundColor(badge.textColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(badge.color)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - Line Detail View (Vertical Diagram + Nearby Departures + RFI Works)

struct RailwayLineDetailView: View {
    let line: PersonalRailwayLine
    let news: [NewsItem]

    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var personalLinesManager: PersonalLinesManager

    @State private var selectedWorkItem: NewsItem? = nil
    @State private var expandedRealtimeGuids: Set<String> = []
    @State private var showStationVisibilitySheet: Bool = false
    @State private var showPassanteDetail: Bool = false
    @State private var selectedDetailStation: Station? = nil

    private var visibleStations: [Station] {
        personalLinesManager.visibleResolvedStations(
            for: line,
            trainManager: manager,
            passanteManager: passanteManager
        )
    }

    private var activeNearby: Station? {
        personalLinesManager.nearestStation(
            on: line,
            visibleStations: visibleStations,
            activeNearby: locationManager.manualNearbyStation ?? locationManager.nearbyStation,
            userLocation: locationManager.userLocation
        )
    }

    private var nearbyDepartures: LineNearbyDepartures? {
        guard let station = activeNearby else { return nil }
        let key = TrainManager.canonicalStationKey(for: station)
        guard let cached = personalLinesManager.nearbyDeparturesByLine[line.id],
              cached.stationKey == key else {
            return nil
        }
        return cached
    }

    private var relevantAlerts: [NewsItem] {
        personalLinesManager.relevantNews(for: line, from: news)
    }

    private var isSaved: Bool {
        personalLinesManager.isLineSaved(id: line.id)
    }

    private var isLoadingNearby: Bool {
        personalLinesManager.loadingNearbyLineIDs.contains(line.id)
    }

    var body: some View {
        List {
            // Header
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        LineCodeBadge(line: line)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("\(line.kind.rawValue) · \(line.effectiveRegion)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if !line.subtitle.isEmpty {
                        Text(line.subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if line.usesPassanteTunnel {
                        Button {
                            showPassanteDetail = true
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: passanteManager.passanteTunnelHealthColor))
                                    .frame(width: 8, height: 8)
                                Text("Passante: \(passanteManager.passanteTunnelHealthMessage)")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            }

            // Upcoming departures from nearby/selected station
            Section {
                if let station = activeNearby {
                    if isLoadingNearby && nearbyDepartures == nil {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Carico partenze da \(station.formattedName.compactStationName)...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    } else if let departures = nearbyDepartures?.departures, !departures.isEmpty {
                        ForEach(Array(departures.prefix(4))) { train in
                            nearbyDepartureRow(train)
                        }
                    } else {
                        Text("Nessuna partenza imminente di questa linea da \(station.formattedName.compactStationName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    }
                } else {
                    Text("Nessuna fermata della linea entro 10 km. Tieni premuta una stazione sullo schema sotto per vederne le partenze.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                }
            } header: {
                if let station = activeNearby {
                    Text("Prossime partenze da \(station.formattedName.compactStationName)")
                } else {
                    Text("Stazione vicina")
                }
            }

            // Vertical diagram (with Y-fork branches + hardcoded interchanges)
            Section {
                VerticalRailwayLineDiagramView(
                    line: line,
                    visibleStations: visibleStations,
                    nearbyStation: activeNearby,
                    directionBadges: nearbyDepartures?.directionBadges,
                    isLoadingNearby: isLoadingNearby,
                    showsNearbyDepartures: true,
                    maxVisibleStations: nil,
                    onSelectStation: { station in
                        selectedDetailStation = station
                    },
                    onSelectManualStation: { station in
                        Haptics.play(.heavy)
                        locationManager.manualNearbyStation = station
                        if line.usesPassanteTunnel {
                            passanteManager.selectPassanteStation(station, manager: manager)
                        }
                        Task {
                            await refreshOnDemand(force: true)
                        }
                    }
                )
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            } header: {
                HStack {
                    Text("Percorso e fermate (\(visibleStations.count))")
                    Spacer()
                    Button("Filtra") {
                        showStationVisibilitySheet = true
                    }
                    .font(.caption.weight(.semibold))
                }
            }

            // Pertinent RFI works & alerts (computed in-memory from downloaded news)
            if !relevantAlerts.isEmpty {
                Section {
                    ForEach(relevantAlerts) { item in
                        if item.isWorksCategory || item.hasNoticeDetail {
                            RFILavoroCardView(item: item, showRegionBadge: true) {
                                selectedWorkItem = item
                            }
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                        } else {
                            let key = item.guid ?? item.id.uuidString
                            RFIRealtimeCardView(
                                item: item,
                                isExpanded: expandedRealtimeGuids.contains(key),
                                showRegionBadge: true
                            ) {
                                if expandedRealtimeGuids.contains(key) {
                                    expandedRealtimeGuids.remove(key)
                                } else {
                                    expandedRealtimeGuids.insert(key)
                                }
                            }
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                        }
                    }
                } header: {
                    Text("Lavori e avvisi RFI")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(line.code)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            UserInterestTelemetryManager.shared.recordLineView(
                lineID: line.id,
                code: line.code,
                name: line.name,
                kind: line.kind.rawValue,
                region: line.effectiveRegion
            )
        }
        .navigationDestination(item: $selectedDetailStation) { station in
            SmartBoardView(station: station)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        if isSaved {
                            personalLinesManager.removeLine(id: line.id, passanteManager: passanteManager)
                        } else {
                            personalLinesManager.addLine(line, passanteManager: passanteManager)
                        }
                    } label: {
                        Image(systemName: isSaved ? "star.fill" : "star")
                            .foregroundColor(isSaved ? .yellow : .primary)
                    }
                    .accessibilityLabel(isSaved ? "Rimuovi dai preferiti" : "Salva linea")

                    if activeNearby != nil {
                        Button {
                            Task { await refreshOnDemand(force: true) }
                        } label: {
                            if isLoadingNearby {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .accessibilityLabel("Aggiorna partenze stazione vicina")
                    }
                }
            }
        }
        .refreshable {
            if line.usesPassanteTunnel {
                _ = await passanteManager.refreshTunnelHealthIfNeeded(manager: manager, minInterval: 0, force: true)
            }
            await refreshOnDemand(force: true)
        }
        .task(id: "\(line.id)|\(activeNearby.map { TrainManager.canonicalStationKey(for: $0) } ?? "none")") {
            if line.usesPassanteTunnel {
                _ = await passanteManager.refreshTunnelHealthIfNeeded(manager: manager, minInterval: 240)
            }
            await refreshOnDemand(force: false)
        }
        .sheet(isPresented: $showStationVisibilitySheet) {
            LineStationVisibilitySheet(line: line)
                .environmentObject(personalLinesManager)
                .environmentObject(passanteManager)
        }
        .sheet(isPresented: $showPassanteDetail) {
            PassanteTunnelDetailView()
                .environmentObject(manager)
                .environmentObject(passanteManager)
        }
        .sheet(item: $selectedWorkItem) { item in
            RFILavoroDetailSheet(item: item)
        }
    }

    private func nearbyDepartureRow(_ train: Train) -> some View {
        let isCancelled = train.delay.localizedCaseInsensitiveContains("soppresso")
            || train.delay.localizedCaseInsensitiveContains("cancellat")
        let delayMinutes = TrainManager.parseDelayMinutes(from: train.delay) ?? 0
        let delayKind: SemanticStatusKind = {
            if isCancelled || delayMinutes >= 15 { return .disrupted }
            if delayMinutes > 0 { return .warning }
            return .regular
        }()
        let delayLabel = isCancelled ? "Soppresso" : (train.delay.isEmpty ? "In orario" : train.delay)

        return NavigationLink {
            TrainStopsView(train: train, showCloseButton: false)
        } label: {
            HStack(spacing: 10) {
                TrainCategoryBadge(category: train.category, compact: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(train.number) → \(train.destination.compactStationName)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(train.time)
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundColor(.blue)
                        if !train.platform.isEmpty && train.platform != "--" {
                            Text("· Bin. \(train.platform)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                StatusBadgePill(text: delayLabel, kind: delayKind, compact: true)
            }
            .padding(.vertical, 2)
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    private func refreshOnDemand(force: Bool) async {
        guard let station = activeNearby else { return }
        await personalLinesManager.refreshNearbyDepartures(
            for: line,
            station: station,
            visibleStations: visibleStations,
            trainManager: manager,
            passanteManager: passanteManager,
            force: force
        )
    }
}

// MARK: - Manage Lines Sheet with Peek View Before Adding

struct LineManagementSheet: View {
    let news: [NewsItem]

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var personalLinesManager: PersonalLinesManager

    @State private var searchText: String = ""
    @State private var customOriginName: String = ""
    @State private var customOriginID: String = ""
    @State private var customDestName: String = ""
    @State private var customDestID: String = ""
    @State private var pickingOrigin: Bool = false
    @State private var pickingDest: Bool = false

    private var filteredCatalog: [PersonalRailwayLine] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return RailwayLineCatalog.curatedCatalog }
        return RailwayLineCatalog.curatedCatalog.filter { line in
            line.name.localizedCaseInsensitiveContains(q)
            || line.code.localizedCaseInsensitiveContains(q)
            || line.subtitle.localizedCaseInsensitiveContains(q)
            || line.effectiveRegion.localizedCaseInsensitiveContains(q)
            || line.stations.contains(where: { $0.localizedCaseInsensitiveContains(q) })
        }
    }

    private enum CatalogSectionBucket: CaseIterable, Identifiable {
        case lombardySuburban
        case lombardyRegional
        case highSpeed
        case intercity
        case international
        case airport
        case italySuburban
        case northwestRegional
        case northeastRegional
        case centerRegional
        case southIslandsRegional

        var id: Self { self }

        var title: String {
            switch self {
            case .lombardySuburban: return "Suburbane Milano, Lombardia e TILO"
            case .lombardyRegional: return "Regionali e RegioExpress Lombardia"
            case .highSpeed: return "Alta Velocità (Frecciarossa / Italo)"
            case .intercity: return "Intercity e Intercity Notte"
            case .international: return "Linee Internazionali (EC / RJ / TGV)"
            case .airport: return "Collegamenti Aeroportuali"
            case .italySuburban: return "Suburbane e Metropolitane Italia"
            case .northwestRegional: return "Direttrici Regionali — Nord-Ovest"
            case .northeastRegional: return "Direttrici Regionali — Nord-Est ed Emilia"
            case .centerRegional: return "Direttrici Regionali — Centro"
            case .southIslandsRegional: return "Direttrici Regionali — Sud e Isole"
            }
        }
    }

    private func sectionBucket(for line: PersonalRailwayLine) -> CatalogSectionBucket {
        let reg = line.effectiveRegion
        switch line.kind {
        case .highSpeed:
            return .highSpeed
        case .intercity:
            return .intercity
        case .international:
            return .international
        case .airport:
            return .airport
        case .suburban:
            return reg.contains("Lombardia") ? .lombardySuburban : .italySuburban
        case .regional, .personalCorridor:
            if reg.contains("Lombardia") && !reg.hasPrefix("Emilia-Romagna") && !reg.hasPrefix("Veneto") {
                return .lombardyRegional
            }
            if reg.hasPrefix("Piemonte") || reg.hasPrefix("Liguria") || reg.hasPrefix("Valle d'Aosta") {
                return .northwestRegional
            }
            if reg.hasPrefix("Emilia-Romagna") || reg.hasPrefix("Veneto") || reg.hasPrefix("Trentino") || reg.hasPrefix("Friuli") || reg.contains("FVG") {
                return .northeastRegional
            }
            if reg.hasPrefix("Toscana") || reg.hasPrefix("Umbria") || reg.hasPrefix("Marche") || reg.hasPrefix("Lazio") || reg.hasPrefix("Abruzzo") || reg.hasPrefix("Molise") {
                return .centerRegional
            }
            return .southIslandsRegional
        }
    }

    private func lines(in bucket: CatalogSectionBucket) -> [PersonalRailwayLine] {
        filteredCatalog.filter { sectionBucket(for: $0) == bucket }
    }

    var body: some View {
        NavigationStack {
            List {
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !personalLinesManager.suggestedLines.isEmpty {
                    Section("Suggerite dalle tue abitudini") {
                        ForEach(personalLinesManager.suggestedLines) { suggestion in
                            catalogRow(suggestion.line, subtitleOverride: suggestion.reason)
                        }
                    }
                }

                ForEach(CatalogSectionBucket.allCases) { bucket in
                    let bucketLines = lines(in: bucket)
                    if !bucketLines.isEmpty {
                        Section(bucket.title) {
                            ForEach(bucketLines) { line in
                                let subtitle = (bucket == .lombardySuburban || bucket == .lombardyRegional || bucket == .highSpeed || bucket == .airport)
                                    ? line.subtitle
                                    : "\(line.effectiveRegion) · \(line.subtitle)"
                                catalogRow(line, subtitleOverride: subtitle)
                            }
                        }
                    }
                }

                Section("Crea direttrice personalizzata") {
                    Button {
                        pickingOrigin = true
                    } label: {
                        HStack {
                            Text("Stazione di partenza")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(customOriginName.isEmpty ? "Seleziona" : customOriginName)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        pickingDest = true
                    } label: {
                        HStack {
                            Text("Stazione di arrivo")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(customDestName.isEmpty ? "Seleziona" : customDestName)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        let corridor = RailwayLineCatalog.buildCorridorLine(
                            origin: customOriginName,
                            destination: customDestName
                        )
                        personalLinesManager.addLine(corridor, passanteManager: passanteManager)
                        customOriginName = ""
                        customDestName = ""
                    } label: {
                        Label("Salva direttrice", systemImage: "plus.circle.fill")
                    }
                    .disabled(customOriginName.isEmpty || customDestName.isEmpty || customOriginName == customDestName)
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Cerca S6, RE4, SFM1, FL1, AV, IC, stazioni...")
            .navigationTitle("Aggiungi Linee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fatto") { dismiss() }
                }
            }
            .sheet(isPresented: $pickingOrigin) {
                StationSelectionSheet(
                    selectedName: $customOriginName,
                    selectedID: $customOriginID,
                    title: "Partenza direttrice"
                )
                .environmentObject(manager)
                .environmentObject(locationManager)
            }
            .sheet(isPresented: $pickingDest) {
                StationSelectionSheet(
                    selectedName: $customDestName,
                    selectedID: $customDestID,
                    title: "Arrivo direttrice"
                )
                .environmentObject(manager)
                .environmentObject(locationManager)
            }
        }
    }

    private func catalogRow(_ line: PersonalRailwayLine, subtitleOverride: String) -> some View {
        let saved = personalLinesManager.isLineSaved(id: line.id)
        return HStack(spacing: 10) {
            NavigationLink {
                LineCatalogPreviewView(line: line, news: news, isSheet: false)
            } label: {
                HStack(spacing: 10) {
                    LineCodeBadge(line: line)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text(subtitleOverride)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Button {
                Haptics.play(.medium)
                if saved {
                    personalLinesManager.removeLine(id: line.id, passanteManager: passanteManager)
                } else {
                    personalLinesManager.addLine(line, passanteManager: passanteManager)
                }
            } label: {
                Image(systemName: saved ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundColor(saved ? .green : .accentColor)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel(saved ? "Rimuovi \(line.code)" : "Aggiungi \(line.code)")
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}

// MARK: - Peek / Preview Before Adding a Line (Vertical Schema + Branches + Interchanges)

struct LineCatalogPreviewView: View {
    let line: PersonalRailwayLine
    let news: [NewsItem]
    let isSheet: Bool

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var personalLinesManager: PersonalLinesManager

    @State private var selectedPreviewStation: Station? = nil

    private var isSaved: Bool {
        personalLinesManager.isLineSaved(id: line.id)
    }

    private var visibleStations: [Station] {
        personalLinesManager.visibleResolvedStations(
            for: line,
            trainManager: manager,
            passanteManager: passanteManager
        )
    }

    private var nearbyStation: Station? {
        personalLinesManager.nearestStation(
            on: line,
            visibleStations: visibleStations,
            activeNearby: locationManager.manualNearbyStation ?? locationManager.nearbyStation,
            userLocation: locationManager.userLocation
        )
    }

    private var relevantAlertsCount: Int {
        personalLinesManager.relevantNews(for: line, from: news).count
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        LineCodeBadge(line: line)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.name)
                                .font(.headline)
                            Text("\(line.kind.rawValue) · \(line.effectiveRegion)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if !line.subtitle.isEmpty {
                        Text(line.subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if relevantAlertsCount > 0 {
                        Text("\(relevantAlertsCount) avvis\(relevantAlertsCount == 1 ? "o" : "i") o lavori RFI pertinenti")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.orange)
                    }
                }
                .padding(.vertical, 4)
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            }

            Section("Percorso e fermate (\(visibleStations.count))") {
                VerticalRailwayLineDiagramView(
                    line: line,
                    visibleStations: visibleStations,
                    nearbyStation: nearbyStation,
                    directionBadges: nil,
                    isLoadingNearby: false,
                    showsNearbyDepartures: false,
                    maxVisibleStations: nil,
                    onSelectStation: { station in
                        selectedPreviewStation = station
                    },
                    onSelectManualStation: nil
                )
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            }

            Section {
                Button {
                    Haptics.play(.medium)
                    if isSaved {
                        personalLinesManager.removeLine(id: line.id, passanteManager: passanteManager)
                    } else {
                        personalLinesManager.addLine(line, passanteManager: passanteManager)
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text(isSaved ? "Rimuovi dalle mie linee" : "Aggiungi alle mie linee")
                            .font(.headline)
                            .foregroundColor(isSaved ? .red : .accentColor)
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(line.code)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            UserInterestTelemetryManager.shared.recordLineView(
                lineID: line.id,
                code: line.code,
                name: line.name,
                kind: line.kind.rawValue,
                region: line.effectiveRegion
            )
        }
        .navigationDestination(item: $selectedPreviewStation) { station in
            SmartBoardView(station: station)
        }
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.play(.medium)
                    if isSaved {
                        personalLinesManager.removeLine(id: line.id, passanteManager: passanteManager)
                    } else {
                        personalLinesManager.addLine(line, passanteManager: passanteManager)
                    }
                } label: {
                    Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle.fill")
                        .foregroundColor(isSaved ? .green : .accentColor)
                }
                .accessibilityLabel(isSaved ? "Rimuovi linea" : "Aggiungi linea")
            }
        }
    }
}

struct LineStationVisibilitySheet: View {
    let line: PersonalRailwayLine
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var personalLinesManager: PersonalLinesManager
    @EnvironmentObject var passanteManager: PassanteManager

    var body: some View {
        NavigationStack {
            List(line.stations, id: \.self) { station in
                let isHidden = personalLinesManager.isStationHidden(lineID: line.id, stationName: station)
                    || (passanteManager.hiddenSuburbanStations[line.id]?.contains(station) ?? false)
                Button {
                    personalLinesManager.toggleStationVisibility(
                        lineID: line.id,
                        stationName: station,
                        passanteManager: passanteManager
                    )
                } label: {
                    HStack {
                        Text(station)
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: isHidden ? "eye.slash" : "checkmark.circle.fill")
                            .foregroundColor(isHidden ? .secondary : line.color)
                    }
                }
            }
            .navigationTitle("Fermate su \(line.code)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fatto") { dismiss() }
                }
            }
        }
    }
}
