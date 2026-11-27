import SwiftUI

enum TrainsFilterMode: String, CaseIterable, Identifiable {
    case all = "Tutti"
    case inTransit = "In viaggio"
    case delayedOrAlert = "Con ritardi"
    case regular = "Regolari"
    case withAlerts = "Con avvisi attivi"

    var id: String { rawValue }
}

struct TrainsTabRootView: View {
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var usageTracker: UsageTracker
    @EnvironmentObject var navigationCoordinator: MainNavigationCoordinator

    @AppStorage("metroMilanoBetaEnabled") private var metroMilanoBetaEnabled = false
    @AppStorage("trainsRecentlyViewedExpanded_v1") private var isRecentTrainsExpanded = false

    @Binding var isMetroModeActive: Bool
    let isActiveTab: Bool
    let hasUrgentNews: Bool
    let onOpenNotifications: () -> Void
    let onOpenHistory: () -> Void
    let onOpenNews: () -> Void
    let onOpenProfile: () -> Void

    @State private var selectedTrainForNotification: SavedTrain? = nil
    @State private var showItaloUnsupportedAlert: Bool = false
    @State private var liveActivityErrorMessage: String? = nil

    private var sortedFavoriteTrains: [SavedTrain] {
        TrainManager.sortedTrainsByDeparture(
            manager.favoriteTrains,
            snapshots: manager.liveTrainSnapshots
        )
    }

    private var recentSuggestions: [SavedTrain] {
        let favNumbers = Set(manager.favoriteTrains.map(\.number))
        return manager.unifiedRecentTrains.filter { !favNumbers.contains($0.number) }
    }

    var body: some View {
        List {
            if manager.favoriteTrains.isEmpty {
                Section {
                    InOrarioEmptyStateCard(
                        systemImage: "tram.fill",
                        tint: .blue,
                        title: "Nessun treno preferito",
                        message: "Scorri verso sinistra su un treno visto di recente per salvarlo nei preferiti, oppure verso destra per attivare la Dynamic Island.",
                        primaryActionTitle: "Cerca un treno",
                        primaryActionIcon: "magnifyingglass",
                        onPrimaryAction: {
                            navigationCoordinator.openSearch(scope: .trainsAndStations)
                        }
                    )
                }
            } else {
                Section {
                    favoriteTrainsSectionBody
                }
            }

            if !recentSuggestions.isEmpty {
                Section {
                    if isRecentTrainsExpanded {
                        ForEach(recentSuggestions.prefix(6)) { recent in
                            NavigationLink {
                                TrainStopsView(
                                    train: manager.createDummyTrain(from: recent),
                                    showCloseButton: false
                                )
                            } label: {
                                TrainSettingsRowView(
                                    savedTrain: recent,
                                    snapshot: manager.liveTrainSnapshots[recent.number],
                                    isFavorite: false,
                                    isLiveActivityActive: manager.activeLiveActivities.contains(recent.number),
                                    onToggleFavorite: {
                                        addRecentTrainToFavorites(recent)
                                    }
                                )
                            }
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                dynamicIslandSwipeButton(for: recent)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    addRecentTrainToFavorites(recent)
                                } label: {
                                    Label("Preferito", systemImage: "star.fill")
                                }
                                .tint(.yellow)
                            }
                            .contextMenu {
                                trainContextMenuButtons(for: recent, isFavorite: false)
                            } preview: {
                                TrainQuickPreviewView(
                                    savedTrain: recent,
                                    initialSnapshot: manager.liveTrainSnapshots[recent.number]
                                )
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
                            isRecentTrainsExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Treni recenti")
                            Spacer()
                            Image(systemName: isRecentTrainsExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Treni")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            InOrarioTabToolbar(
                tab: .trains,
                hasUrgentNews: hasUrgentNews,
                isMetroBetaEnabled: metroMilanoBetaEnabled,
                isMetroModeActive: $isMetroModeActive,
                onSearch: { navigationCoordinator.openContextualSearch(for: .trains) },
                onOpenAssistant: { navigationCoordinator.openAssistantSearch(for: .trains) },
                onOpenHistory: onOpenHistory,
                onOpenNotifications: onOpenNotifications,
                onOpenNews: onOpenNews,
                onOpenProfile: onOpenProfile
            )
        }
        .refreshable {
            await manager.refreshFavoriteTrainSnapshotsIfNeeded(force: true, ttl: 120)
            if isRecentTrainsExpanded {
                await manager.enrichRecentTrainTimesIfNeeded()
            }
        }
        .task(id: isActiveTab) {
            guard isActiveTab else { return }
            await manager.refreshFavoriteTrainSnapshotsIfNeeded(force: false, ttl: 120)
        }
        .task(id: "\(isActiveTab)|\(isRecentTrainsExpanded)") {
            guard isActiveTab, isRecentTrainsExpanded else { return }
            await manager.enrichRecentTrainTimesIfNeeded()
        }
        .sheet(item: $selectedTrainForNotification) { target in
            if let idx = manager.favoriteTrains.firstIndex(where: { $0.number == target.number }) {
                TrainNotificationConfigSheet(train: $manager.favoriteTrains[idx])
                    .environmentObject(manager)
                    .environmentObject(passanteManager)
            }
        }
        .alert("Non disponibile per Italo", isPresented: $showItaloUnsupportedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("In Orario supporta Dynamic Island e notifiche automatiche solo per i treni Trenitalia e Trenord.")
        }
        .alert("Dynamic Island", isPresented: Binding(
            get: { liveActivityErrorMessage != nil },
            set: { if !$0 { liveActivityErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(liveActivityErrorMessage ?? "")
        }
    }

    private func addRecentTrainToFavorites(_ recent: SavedTrain) {
        Haptics.notify(.success)
        withAnimation(.snappy(duration: 0.25)) {
            manager.toggleFavorite(
                trainNumber: recent.number,
                description: recent.description,
                departureTime: recent.departureTime
            )
        }
        Task {
            await manager.enrichFavoriteTrainData(trainNumber: recent.number)
        }
    }

    @ViewBuilder
    private var favoriteTrainsSectionBody: some View {
        ForEach(sortedFavoriteTrains) { saved in
            NavigationLink {
                TrainStopsView(
                    train: manager.createDummyTrain(from: saved),
                    showCloseButton: false
                )
            } label: {
                TrainSettingsRowView(
                    savedTrain: saved,
                    snapshot: manager.liveTrainSnapshots[saved.number],
                    isFavorite: true,
                    isLiveActivityActive: manager.activeLiveActivities.contains(saved.number),
                    onToggleFavorite: {
                        Haptics.play(.light)
                        withAnimation(.snappy(duration: 0.25)) {
                            manager.toggleFavorite(
                                trainNumber: saved.number,
                                description: saved.description,
                                departureTime: saved.departureTime
                            )
                        }
                    }
                )
            }
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                dynamicIslandSwipeButton(for: saved)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    Haptics.play(.light)
                    withAnimation(.snappy(duration: 0.25)) {
                        manager.toggleFavorite(
                            trainNumber: saved.number,
                            description: saved.description,
                            departureTime: saved.departureTime
                        )
                    }
                } label: {
                    Label("Rimuovi dai preferiti", systemImage: "star.slash.fill")
                }
            }
            .contextMenu {
                trainContextMenuButtons(for: saved, isFavorite: true)
            } preview: {
                TrainQuickPreviewView(
                    savedTrain: saved,
                    initialSnapshot: manager.liveTrainSnapshots[saved.number]
                )
            }
        }
    }

    @ViewBuilder
    private func dynamicIslandSwipeButton(for saved: SavedTrain) -> some View {
        let isActive = manager.activeLiveActivities.contains(saved.number)
        Button {
            triggerQuickLiveActivity(for: saved)
        } label: {
            Label(
                isActive ? "Ferma monitoraggio" : "Dynamic Island",
                systemImage: isActive ? "livephoto.slash" : "livephoto.play"
            )
        }
        .tint(isActive ? .red : .green)
    }

    @ViewBuilder
    private func trainContextMenuButtons(for saved: SavedTrain, isFavorite: Bool) -> some View {
        let isActive = manager.activeLiveActivities.contains(saved.number)
        Button {
            triggerQuickLiveActivity(for: saved)
        } label: {
            Label(
                isActive ? "Ferma monitoraggio" : "Dynamic Island",
                systemImage: isActive ? "livephoto.slash" : "livephoto.play"
            )
        }

        Button {
            if isFavorite {
                selectedTrainForNotification = saved
            } else {
                openNotificationsSavingIfNeeded(for: saved)
            }
        } label: {
            Label("Configura avvisi", systemImage: "bell.fill")
        }

        Button {
            manager.toggleFavorite(
                trainNumber: saved.number,
                description: saved.description,
                departureTime: saved.departureTime
            )
            if !isFavorite {
                Task {
                    await manager.enrichFavoriteTrainData(trainNumber: saved.number)
                }
            }
        } label: {
            Label(
                isFavorite ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti",
                systemImage: isFavorite ? "star.slash" : "star.fill"
            )
        }

        if !isFavorite {
            Button(role: .destructive) {
                manager.removeRecentTrain(number: saved.number)
            } label: {
                Label("Rimuovi dai recenti", systemImage: "trash")
            }
        }
    }

    private func triggerQuickLiveActivity(for saved: SavedTrain) {
        Task {
            let outcome = await manager.toggleQuickLiveActivity(for: saved)
            switch outcome {
            case .started, .stopped:
                break
            case .italoUnsupported:
                showItaloUnsupportedAlert = true
            case .failed(let msg):
                liveActivityErrorMessage = msg
            }
        }
    }

    private func openNotificationsSavingIfNeeded(for saved: SavedTrain) {
        if !manager.isFavorite(trainNumber: saved.number) {
            manager.toggleFavorite(
                trainNumber: saved.number,
                description: saved.description,
                departureTime: saved.departureTime
            )
        }
        if let savedEntry = manager.favoriteTrains.first(where: { $0.number == saved.number }) {
            selectedTrainForNotification = savedEntry
        }
    }

    private func hasNotificationsEnabled(for saved: SavedTrain) -> Bool {
        manager.remoteNotificationsEnabled
        && manager.trainNotificationsEnabled
        && saved.hasActiveNotifications
    }
}

// MARK: - Unified Native iOS Settings Train Row

struct TrainSettingsRowView: View {
    @EnvironmentObject var manager: TrainManager
    let savedTrain: SavedTrain
    let snapshot: TrainLiveSnapshot?
    let isFavorite: Bool
    let isLiveActivityActive: Bool
    let onToggleFavorite: () -> Void

    private var hasNotifications: Bool {
        manager.remoteNotificationsEnabled
        && manager.trainNotificationsEnabled
        && savedTrain.hasActiveNotifications
    }

    private var endpoints: (origin: String?, destination: String) {
        if let snapshot, let dest = snapshot.destination, !dest.isEmpty {
            return (snapshot.origin, dest)
        }
        return savedTrain.parsedEndpoints
    }

    private var routeLineText: String {
        let dest = endpoints.destination.compactStationName
        if let origin = endpoints.origin?.compactStationName, !origin.isEmpty, origin != dest {
            return "\(origin) → \(dest)"
        }
        return dest
    }

    private var timeRange: (departure: String, arrival: String?)? {
        if let stops = snapshot?.stops, let first = stops.first, let last = stops.last {
            let dep = first.time.trimmingCharacters(in: .whitespacesAndNewlines)
            let arr = last.time.trimmingCharacters(in: .whitespacesAndNewlines)
            if !dep.isEmpty && dep != "--:--" {
                return (dep, (arr.isEmpty || arr == "--:--") ? nil : arr)
            }
        }
        return savedTrain.formattedTimeRange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 8) {
                TrainCategoryBadge(category: snapshot?.category ?? savedTrain.resolvedCategoryCode(), compact: true)

                Text(savedTrain.number)
                    .font(.headline.weight(.bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let times = timeRange {
                    HStack(spacing: 3) {
                        Text(times.departure)
                        if let arr = times.arrival {
                            Text("→")
                                .foregroundColor(.secondary)
                            Text(arr)
                        }
                    }
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 6)

                TrainLiveDelayPill(snapshot: snapshot, compact: true)

                if !isFavorite {
                    Button(action: onToggleFavorite) {
                        Image(systemName: "star")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Aggiungi ai preferiti")
                }
            }

            HStack(spacing: 8) {
                Text(routeLineText)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if hasNotifications {
                    Image(systemName: "bell.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }

                if isLiveActivityActive {
                    Image(systemName: "livephoto.play")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.green)
                }
            }

            if let snapshot, snapshot.isDeparted && !snapshot.isArrived && !snapshot.isCancelled,
               let lastStation = snapshot.lastStation {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(snapshot.lastTime != nil ? "\(lastStation.compactStationName) · \(snapshot.lastTime!)" : lastStation.compactStationName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Self-Contained 3D Touch / Haptic Touch Live Train Preview (Crash-Safe)

struct TrainQuickPreviewView: View {
    let savedTrain: SavedTrain
    let initialSnapshot: TrainLiveSnapshot?

    @State private var stops: [Stop]
    @State private var status: TrainStatus
    @State private var isLoading: Bool = false

    init(savedTrain: SavedTrain, initialSnapshot: TrainLiveSnapshot? = nil) {
        self.savedTrain = savedTrain
        self.initialSnapshot = initialSnapshot
        _stops = State(initialValue: initialSnapshot?.stops ?? [])
        _status = State(initialValue: initialSnapshot?.status ?? TrainStatus())
    }

    private var delayBadge: (text: String, color: Color)? {
        if status.statusMessage.localizedCaseInsensitiveContains("Soppresso") || status.cancellationNote != nil {
            return ("Soppresso", .red)
        }
        guard status.isDeparted && !status.isArrived && !stops.isEmpty else {
            return nil
        }
        let delay = TrainManager.resolveSnapshotDelay(stops: stops)
        if delay >= 15 { return ("+\(delay)'", .red) }
        if delay > 0 { return ("+\(delay)'", .orange) }
        if delay < 0 { return ("-\(abs(delay))'", .green) }
        return ("In orario", .green)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TrainCategoryBadge(category: status.detectedCategory ?? savedTrain.resolvedCategoryCode(), compact: false)
                Text(savedTrain.number)
                    .font(.headline.bold())
                Spacer()
                if let badge = delayBadge {
                    Text(badge.text)
                        .font(.caption.bold())
                        .foregroundColor(badge.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(badge.color.opacity(0.14))
                        .clipShape(Capsule())
                }
            }

            let originName = stops.first?.stationName.compactStationName ?? savedTrain.parsedEndpoints.origin?.compactStationName
            let destName = stops.last?.stationName.compactStationName ?? savedTrain.parsedEndpoints.destination.compactStationName
            Text(originName != nil ? "\(originName!) → \(destName)" : destName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            if status.lastStation != "--" && !status.lastStation.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.caption2)
                    Text(
                        status.lastTime != "--" && !status.lastTime.isEmpty
                            ? "\(status.lastStation.compactStationName) · \(status.lastTime)"
                            : status.lastStation.compactStationName
                    )
                }
                .font(.caption)
                .foregroundColor(.secondary)
            } else if !status.statusMessage.isEmpty {
                Text(status.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            if isLoading && stops.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("Caricamento fermate...")
                        .font(.caption)
                    Spacer()
                }
                .padding(.vertical, 28)
            } else if stops.isEmpty {
                Text("Fermate non ancora disponibili.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(stops) { stop in
                            HStack(spacing: 8) {
                                Text(stop.time)
                                    .font(.caption.monospacedDigit().weight(.semibold))
                                    .foregroundColor(stop.actualTime != nil ? .secondary : .primary)
                                    .frame(width: 44, alignment: .leading)

                                Circle()
                                    .fill(stop.isSuppressed ? .red : (stop.actualTime != nil ? .green : .secondary.opacity(0.35)))
                                    .frame(width: 7, height: 7)

                                Text(stop.stationName.compactStationName)
                                    .font(.caption.weight(stop.actualTime == nil ? .medium : .regular))
                                    .foregroundColor(stop.isSuppressed ? .red : .primary)
                                    .lineLimit(1)

                                Spacer()

                                if let bin = stop.actualPlatform ?? stop.plannedPlatform, !bin.isEmpty, bin != "-" {
                                    Text("Bin. \(bin)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 330, height: 340)
        .background(Color(.systemGroupedBackground))
        .task {
            guard stops.isEmpty else { return }
            isLoading = true
            let endpoints = savedTrain.parsedEndpoints
            let result = await TrainRepository.shared.getLiveStops(
                for: savedTrain.number,
                category: savedTrain.category,
                destination: endpoints.destination,
                origin: endpoints.origin,
                scheduledTime: savedTrain.departureTime,
                force: false
            )
            self.stops = result.stops
            self.status = result.status
            self.isLoading = false
        }
    }
}
