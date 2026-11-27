import SwiftUI

enum StationsFilterMode: String, CaseIterable, Identifiable {
    case all = "Tutte"
    case attention = "Con criticità"

    var id: String { rawValue }
}

struct StationsTabRootView: View {
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var usageTracker: UsageTracker
    @EnvironmentObject var guessingEngine: TrainGuessingEngine
    @EnvironmentObject var metroManager: MetroManager
    @EnvironmentObject var metroCache: MetroCache
    @EnvironmentObject var navigationCoordinator: MainNavigationCoordinator

    @AppStorage("metroMilanoBetaEnabled") private var metroMilanoBetaEnabled = false
    @AppStorage("stationsRecentlyViewedExpanded_v1") private var isRecentStationsExpanded = false

    @Binding var isMetroModeActive: Bool
    let isActiveTab: Bool
    let hasUrgentNews: Bool
    let onOpenNotifications: () -> Void
    let onOpenHistory: () -> Void
    let onOpenNews: () -> Void
    let onOpenProfile: () -> Void

    private var pinnedNearbyStation: Station? {
        locationManager.manualNearbyStation ?? locationManager.nearbyStation
    }

    private var remainingSavedStations: [Station] {
        manager.myStations.filter { st in
            !(pinnedNearbyStation?.matches(st) ?? false)
        }
    }

    private var recentSuggestions: [Station] {
        let savedKeys = Set(manager.myStations.map { TrainManager.canonicalStationKey(for: $0) })
        let nearbyKey = pinnedNearbyStation.map { TrainManager.canonicalStationKey(for: $0) }
        return manager.unifiedRecentStations.prefix(6).compactMap { recent in
            let st = manager.resolveStation(name: recent.nomeLungo, fallbackVtID: recent.vtID, fallbackRfiID: nil)
            let key = TrainManager.canonicalStationKey(for: st)
            if savedKeys.contains(key) || key == nearbyKey || manager.myStations.contains(where: { $0.matches(st) }) {
                return nil
            }
            return st
        }
    }

    private var allStationsToMonitor: [Station] {
        var list: [Station] = []
        if let nearby = pinnedNearbyStation {
            list.append(nearby)
        }
        list.append(contentsOf: manager.myStations)
        if isRecentStationsExpanded {
            list.append(contentsOf: recentSuggestions)
        }
        return list
    }

    var body: some View {
        List {
            if manager.myStations.isEmpty && pinnedNearbyStation == nil {
                Section {
                    InOrarioEmptyStateCard(
                        systemImage: "building.2.fill",
                        tint: .blue,
                        title: "Nessuna stazione salvata",
                        message: "Cerca una stazione e aggiungila ai preferiti per vedere in tempo reale lo stato della circolazione e accedere subito al tabellone.",
                        primaryActionTitle: "Cerca stazione",
                        primaryActionIcon: "magnifyingglass",
                        onPrimaryAction: {
                            navigationCoordinator.openSearch(scope: .trainsAndStations)
                        }
                    )
                }
            } else {
                // Unified section: pinned non-reorderable nearest station directly above saved stations (no extra gap)
                if pinnedNearbyStation != nil || !remainingSavedStations.isEmpty {
                    Section {
                        primaryStationsSectionBody
                    } footer: {
                        if !remainingSavedStations.isEmpty {
                            Text("Tieni premuto su una stazione e trascina per riordinarla.")
                        }
                    }
                }
            }

            if !recentSuggestions.isEmpty {
                Section {
                    if isRecentStationsExpanded {
                        ForEach(recentSuggestions, id: \.id) { st in
                            let key = TrainManager.canonicalStationKey(for: st)
                            let snap = manager.stationBoardSnapshots[key]
                            NavigationLink {
                                SmartBoardView(station: st)
                            } label: {
                                RecentStationStatusRow(
                                    station: st,
                                    snapshot: snap,
                                    onToggleSave: {
                                        Haptics.notify(.success)
                                        manager.addMyStation(st)
                                        Task {
                                            await manager.refreshStationSnapshotsIfNeeded(stations: [st], force: true)
                                        }
                                    }
                                )
                            }
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    manager.removeRecentStation(name: st.name, vtID: st.vtID ?? "")
                                    Haptics.play(.light)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .accessibilityLabel("Rimuovi")
                            }
                        }

                        Button {
                            Haptics.play(.light)
                            onOpenHistory()
                        } label: {
                            HStack {
                                Text("Mostra tutti")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.accentColor)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    }
                } header: {
                    Button {
                        Haptics.play(.light)
                        withAnimation(.snappy(duration: 0.25)) {
                            isRecentStationsExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Stazioni recenti")
                            Spacer()
                            Image(systemName: isRecentStationsExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if metroMilanoBetaEnabled && !metroManager.favoriteStations.isEmpty {
                Section {
                    ForEach(metroManager.favoriteStations.prefix(4)) { mStation in
                        Button {
                            isMetroModeActive = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "m.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.red)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mStation.displayName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.primary)
                                    Text("Apri sezione Metro Milano")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    }
                } header: {
                    Text("Stazioni Metro Milano")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Stazioni")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            InOrarioTabToolbar(
                tab: .stations,
                hasUrgentNews: hasUrgentNews,
                isMetroBetaEnabled: metroMilanoBetaEnabled,
                isMetroModeActive: $isMetroModeActive,
                onSearch: { navigationCoordinator.openContextualSearch(for: .stations) },
                onOpenAssistant: { navigationCoordinator.openAssistantSearch(for: .stations) },
                onOpenHistory: onOpenHistory,
                onOpenNotifications: onOpenNotifications,
                onOpenNews: onOpenNews,
                onOpenProfile: onOpenProfile
            )
        }
        .refreshable {
            await manager.refreshStationSnapshotsIfNeeded(stations: allStationsToMonitor, force: true, ttl: 300)
        }
        .task(id: "\(isActiveTab)|\(allStationsToMonitor.map { TrainManager.canonicalStationKey(for: $0) }.joined(separator: ","))") {
            guard isActiveTab else { return }
            await manager.refreshStationSnapshotsIfNeeded(stations: allStationsToMonitor, force: false, ttl: 300)
        }
    }

    @ViewBuilder
    private var primaryStationsSectionBody: some View {
        if let nearby = pinnedNearbyStation {
            let isSaved = manager.isMyStation(nearby)
            stationRowLink(station: nearby, isNearby: true)
                .moveDisabled(true)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if isSaved {
                        Button(role: .destructive) {
                            Haptics.play(.light)
                            withAnimation(.snappy(duration: 0.25)) {
                                manager.removeMyStation(nearby)
                            }
                        } label: {
                            Label("Rimuovi dai preferiti", systemImage: "star.slash.fill")
                        }
                    } else {
                        Button {
                            Haptics.notify(.success)
                            withAnimation(.snappy(duration: 0.25)) {
                                manager.addMyStation(nearby)
                            }
                        } label: {
                            Label("Preferito", systemImage: "star.fill")
                        }
                        .tint(.yellow)
                    }
                }
        }

        ForEach(remainingSavedStations, id: \.id) { station in
            stationRowLink(station: station, isNearby: false)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Haptics.play(.light)
                        withAnimation(.snappy(duration: 0.25)) {
                            manager.removeMyStation(station)
                        }
                    } label: {
                        Label("Rimuovi dai preferiti", systemImage: "star.slash.fill")
                    }
                }
        }
        .onMove { source, destination in
            moveRemainingSavedStations(from: source, to: destination)
        }
    }

    private func stationRowLink(station: Station, isNearby: Bool) -> some View {
        let key = TrainManager.canonicalStationKey(for: station)
        return NavigationLink {
            SmartBoardView(station: station)
        } label: {
            PersonalStationCardView(
                station: station,
                snapshot: manager.stationBoardSnapshots[key],
                isNearby: isNearby,
                isAlreadySaved: manager.isMyStation(station),
                onQuickSaveNearby: {
                    Haptics.notify(.success)
                    manager.addMyStation(station)
                }
            )
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    private func moveRemainingSavedStations(from source: IndexSet, to destination: Int) {
        guard let nearby = pinnedNearbyStation,
              let pinnedIdx = manager.myStations.firstIndex(where: { $0.matches(nearby) }) else {
            manager.moveMyStations(from: source, to: destination)
            return
        }
        var rest = remainingSavedStations
        rest.move(fromOffsets: source, toOffset: destination)
        let insertIdx = min(pinnedIdx, rest.count)
        rest.insert(manager.myStations[pinnedIdx], at: insertIdx)
        manager.myStations = rest
        manager.saveFavorites()
    }
}

struct PersonalStationCardView: View {
    let station: Station
    let snapshot: StationBoardSnapshot?
    let isNearby: Bool
    let isAlreadySaved: Bool
    let onQuickSaveNearby: () -> Void

    private var healthDisplay: (text: String, color: Color) {
        guard let snapshot else {
            return ("Aggiornamento in corso...", .gray)
        }
        switch snapshot.circulationState {
        case .regular:
            return (snapshot.healthMessage, .green)
        case .warning:
            return (snapshot.healthMessage, .orange)
        case .disrupted:
            return (snapshot.healthMessage, .red)
        case .noData:
            return (snapshot.healthMessage, .gray)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 7) {
                Text(station.formattedName)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .layoutPriority(1)

                if isNearby {
                    Image(systemName: "location.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.blue)
                        .frame(width: 20, height: 20)
                        .background(Color.blue.opacity(0.14))
                        .clipShape(Circle())
                        .accessibilityLabel("Stazione vicina")
                }

                if !station.uniqueMetroLineBadges.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(station.uniqueMetroLineBadges, id: \.code) { metro in
                            Text(metro.code)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5.5)
                                .padding(.vertical, 2)
                                .background(metro.color)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                Spacer(minLength: 4)

                if isNearby && !isAlreadySaved {
                    Button(action: onQuickSaveNearby) {
                        Image(systemName: "star")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Aggiungi stazione ai preferiti")
                }
            }

            HStack(spacing: 7) {
                Circle()
                    .fill(healthDisplay.color)
                    .frame(width: 9, height: 9)
                Text(healthDisplay.text)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(healthDisplay.color)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let fetched = snapshot?.fetchedAt {
                    Text(SharedFormatters.time.string(from: fetched))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

struct RecentStationStatusRow: View {
    let station: Station
    let snapshot: StationBoardSnapshot?
    let onToggleSave: () -> Void

    private var dotColor: Color {
        guard let snapshot else { return .gray }
        switch snapshot.circulationState {
        case .regular: return .green
        case .warning: return .orange
        case .disrupted: return .red
        case .noData: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text(station.formattedName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let snapshot, snapshot.circulationState == .warning || snapshot.circulationState == .disrupted {
                    Text(snapshot.healthMessage)
                        .font(.caption)
                        .foregroundColor(dotColor)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button(action: onToggleSave) {
                Image(systemName: "star")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Aggiungi ai preferiti")
        }
        .padding(.vertical, 4)
    }
}
