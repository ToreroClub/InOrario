import SwiftUI

private struct TripsPlanBSheetItem: Identifiable {
    let id = UUID()
    let plan: PlanBReportDTO
    let focusedAlternativeId: String?
    let customTitle: String?
    let interactiveCommuteMode: Bool
    let initialIsReturn: Bool
    let autoLoadOnAppear: Bool

    init(
        plan: PlanBReportDTO,
        focusedAlternativeId: String? = nil,
        customTitle: String? = nil,
        interactiveCommuteMode: Bool = false,
        initialIsReturn: Bool = false,
        autoLoadOnAppear: Bool = false
    ) {
        self.plan = plan
        self.focusedAlternativeId = focusedAlternativeId
        self.customTitle = customTitle
        self.interactiveCommuteMode = interactiveCommuteMode
        self.initialIsReturn = initialIsReturn
        self.autoLoadOnAppear = autoLoadOnAppear
    }
}

struct TripsTabRootView: View {
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var usageTracker: UsageTracker
    @EnvironmentObject var cache: MetroCache
    @EnvironmentObject var navigationCoordinator: MainNavigationCoordinator

    @AppStorage("metroMilanoBetaEnabled") private var metroMilanoBetaEnabled = false
    @ObservedObject private var commuteManager = SupporterCommuteManager.shared

    @Binding var isMetroModeActive: Bool
    let isActiveTab: Bool
    let hasUrgentNews: Bool
    let onOpenHistory: () -> Void
    let onOpenNotifications: () -> Void
    let onOpenNews: () -> Void
    let onOpenProfile: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var presentedPlanBSheet: TripsPlanBSheetItem? = nil
    @State private var isLoadingProactivePlan: Bool = false
    @State private var currentMinuteTick: Date = Date()

    @State private var selectedSavedTrip: SavedTrip? = nil
    @State private var selectedHabitRoute: FavoriteRoute? = nil
    @State private var showCommuteSetupSheet = false

    private var proactiveHabitPlan: PlanBReportDTO? {
        guard commuteManager.cachedProactiveHabitSlotKey == proactiveTaskKey else { return nil }
        return commuteManager.cachedProactiveHabitPlan
    }

    private var activeHabitSlot: ActiveHabitCommuteSlot? {
        commuteManager.activeHabitCommuteSlot(leadMinutes: 90, trailMinutes: 30)
    }

    private var proactiveTaskKey: String {
        guard commuteManager.followedTrip == nil,
              commuteManager.homeBannerPlanB == nil,
              let slot = activeHabitSlot else {
            return "none"
        }
        return "\(slot.isReturn ? "R" : "O")|\(slot.timeBand)|\(slot.origins.joined(separator: ","))|\(slot.destinations.joined(separator: ","))"
    }

    private var hasAnyPrimaryTripContent: Bool {
        commuteManager.followedTrip != nil
        || commuteManager.homeBannerPlanB != nil
        || activeHabitSlot != nil
        || commuteManager.hasConfiguredCommute
        || !manager.favoriteRoutes.isEmpty
        || !manager.smartRoutes.isEmpty
        || !manager.savedTrips.isEmpty
    }

    var body: some View {
        List {
            // 1. Viaggio seguito ora (priorità massima) oppure banner reale / proposta proattiva Casa-Lavoro
            if let followed = commuteManager.followedTrip {
                Section {
                    FollowedTripCardView(trip: followed)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Haptics.play(.light)
                                withAnimation {
                                    commuteManager.stopFollowing(manager: manager)
                                }
                            } label: {
                                Label("Smetti di seguire", systemImage: "xmark.circle")
                            }
                        }
                }
            } else if let bannerPlan = commuteManager.homeBannerPlanB {
                Section {
                    bannerPlanRow(bannerPlan)
                }
            } else if let slot = activeHabitSlot {
                proactiveHabitSection(for: slot)
            }

            // 2. Empty state pulito quando non ci sono tratte, viaggi salvati né fascia abituale attiva
            if !hasAnyPrimaryTripContent {
                Section {
                    InOrarioEmptyStateCard(
                        systemImage: "map.fill",
                        tint: .green,
                        title: "Nessuna tratta o viaggio salvato",
                        message: "Usa la ricerca per trovare soluzioni tra due stazioni e salvare tratte abituali per vedere le prime partenze disponibili oppure viaggi specifici.",
                        primaryActionTitle: "Cerca soluzioni di viaggio",
                        primaryActionIcon: "magnifyingglass",
                        onPrimaryAction: {
                            navigationCoordinator.openContextualSearch(for: .trips)
                        }
                    )
                }
            }

            // 3. Tratte abituali (Casa <-> Lavoro automatica + tratte salvate)
            let commuteSlot = commuteManager.currentCommuteRouteSlot(at: currentMinuteTick)
            if commuteSlot != nil || !manager.favoriteRoutes.isEmpty {
                Section {
                    if let slot = commuteSlot {
                        Button {
                            Haptics.play(.light)
                            let placeholder = PlanBReportDTO(
                                title: slot.isReturn ? "Lavoro → Casa" : "Casa → Lavoro",
                                body: "\(formatCityOrStationSummary(slot.origins)) → \(formatCityOrStationSummary(slot.destinations))",
                                incident_type: "simulation",
                                incident_detail: nil,
                                cancelled_train: nil,
                                target_time: SharedFormatters.time.string(from: currentMinuteTick),
                                origins: slot.origins,
                                destinations: slot.destinations,
                                alternatives: [],
                                timestamp: ISO8601DateFormatter().string(from: Date())
                            )
                            presentedPlanBSheet = TripsPlanBSheetItem(
                                plan: placeholder,
                                focusedAlternativeId: nil,
                                customTitle: slot.isReturn ? "Lavoro → Casa" : "Casa → Lavoro",
                                interactiveCommuteMode: true,
                                initialIsReturn: slot.isReturn,
                                autoLoadOnAppear: true
                            )
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: slot.isReturn ? "briefcase.fill" : "house.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(slot.isReturn ? .purple : .blue)
                                    .frame(width: 22, alignment: .center)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(formatCityOrStationSummary(slot.origins)) → \(formatCityOrStationSummary(slot.destinations))")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)

                                    Text("\(slot.isReturn ? "Lavoro → Casa" : "Casa → Lavoro") · \(slot.timeBand)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 4)

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Color(.tertiaryLabel))
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                Haptics.play(.medium)
                                withAnimation {
                                    commuteManager.toggleCommuteRouteDirection(at: currentMinuteTick)
                                }
                            } label: {
                                Label("Inverti", systemImage: "arrow.left.arrow.right")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                Haptics.play(.light)
                                showCommuteSetupSheet = true
                            } label: {
                                Label("Configura", systemImage: "slider.horizontal.3")
                            }
                            .tint(.blue)
                        }
                    }

                    ForEach(manager.favoriteRoutes) { route in
                        NavigationLink {
                            FavoriteRouteSolutionView(route: route)
                        } label: {
                            PersonalRouteCardView(route: route)
                        }
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                Haptics.play(.medium)
                                withAnimation {
                                    manager.setFavoriteRouteReversed(
                                        routeID: route.id,
                                        isReversed: !route.effectiveIsReversed
                                    )
                                }
                            } label: {
                                Label("Inverti", systemImage: "arrow.left.arrow.right")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                withAnimation {
                                    manager.toggleFavoriteRoute(
                                        originName: route.originName,
                                        originID: route.originID,
                                        destName: route.destinationName,
                                        destID: route.destinationID
                                    )
                                }
                            } label: {
                                Label("Rimuovi dai preferiti", systemImage: "star.slash.fill")
                            }
                        }
                    }
                    .onMove { source, destination in
                        manager.moveFavoriteRoutes(from: source, to: destination)
                    }
                } header: {
                    Text("Tratte abituali")
                }
            }

            // 4. Connessioni suburbane
            if !manager.smartRoutes.isEmpty {
                Section {
                    ForEach(manager.smartRoutes) { sRoute in
                        SmartConnectorRouteView(route: sRoute)
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    }
                } header: {
                    Text("Connessioni suburbane")
                }
            }

            // 5. Viaggi salvati (ordine cronologico di partenza, coerente con la Home)
            if !manager.savedTrips.isEmpty {
                let sortedSavedTrips = TrainManager.sortedSavedTripsByDeparture(manager.savedTrips)
                Section {
                    ForEach(sortedSavedTrips) { trip in
                        let solution = trip.asTravelSolution
                        let isFollowed = commuteManager.isSolutionFollowed(solution)
                        PersonalSavedTripCardView(
                            trip: trip,
                            onOpenDetails: {
                                selectedSavedTrip = trip
                            }
                        )
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                toggleFollowSavedTrip(solution: solution, isCurrentlyFollowed: isFollowed)
                            } label: {
                                Label(
                                    isFollowed ? "Smetti di seguire" : "Segui viaggio",
                                    systemImage: isFollowed ? "xmark.circle" : "location.viewfinder"
                                )
                            }
                            .tint(isFollowed ? .red : .blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                withAnimation {
                                    manager.toggleSavedTrip(solution: solution)
                                }
                            } label: {
                                Label("Rimuovi dai preferiti", systemImage: "star.slash.fill")
                            }
                        }
                    }
                } header: {
                    Text("Viaggi salvati")
                }
            }

            // 6. Abitudini apprese (rispetta Impostazioni → Suggerimenti personalizzati)
            if usageTracker.smartSuggestionsEnabled {
                habitsSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Viaggi")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $selectedSavedTrip) { trip in
            TravelSolutionDetailsView(solution: trip.asTravelSolution)
        }
        .navigationDestination(item: $selectedHabitRoute) { route in
            FavoriteRouteSolutionView(route: route)
        }
        .toolbar {
            InOrarioTabToolbar(
                tab: .trips,
                hasUrgentNews: hasUrgentNews,
                isMetroBetaEnabled: metroMilanoBetaEnabled,
                isMetroModeActive: $isMetroModeActive,
                onSearch: { navigationCoordinator.openContextualSearch(for: .trips) },
                onOpenAssistant: { navigationCoordinator.openAssistantSearch(for: .trips) },
                onOpenHistory: onOpenHistory,
                onOpenNotifications: onOpenNotifications,
                onOpenNews: onOpenNews,
                onOpenProfile: onOpenProfile
            )
        }
        .task(id: "\(isActiveTab)|\(proactiveTaskKey)") {
            guard isActiveTab else { return }
            currentMinuteTick = Date()
            await loadProactiveHabitPlan(force: false)
        }
        .task(id: isActiveTab) {
            guard isActiveTab else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { break }
                currentMinuteTick = Date()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && isActiveTab {
                currentMinuteTick = Date()
            }
        }
        .refreshable {
            await commuteManager.refreshFollowedTripStatus(manager: manager, force: true)
            await loadProactiveHabitPlan(force: true)
        }
        .sheet(item: $presentedPlanBSheet, onDismiss: {
            if commuteManager.followedTrip != nil {
                commuteManager.clearPlanBAfterFollow()
            }
        }) { item in
            NavigationStack {
                PlanBDetailView(
                    plan: item.plan,
                    initialFocusedAlternativeId: item.focusedAlternativeId,
                    customTitle: item.customTitle,
                    interactiveCommuteMode: item.interactiveCommuteMode,
                    initialIsReturn: item.initialIsReturn,
                    autoLoadOnAppear: item.autoLoadOnAppear
                )
                .environmentObject(manager)
                .environmentObject(passanteManager)
                .environmentObject(locationManager)
                .environmentObject(cache)
                .environmentObject(usageTracker)
            }
        }
        .sheet(isPresented: $showCommuteSetupSheet) {
            NavigationStack {
                CommuteSetupView(showCloseButton: true)
                    .environmentObject(manager)
                    .environmentObject(locationManager)
                    .environmentObject(passanteManager)
                    .environmentObject(cache)
                    .environmentObject(usageTracker)
            }
        }
    }

    // MARK: - Proactive Commute Proposal Section

    @ViewBuilder
    private func proactiveHabitSection(for slot: ActiveHabitCommuteSlot) -> some View {
        let headerTitle = slot.isReturn
            ? "Ritorno abituale · \(slot.timeBand)"
            : "Viaggio abituale · \(slot.timeBand)"
        let upcomingAlternatives: [PlanBAlternativeItem] = {
            guard let plan = proactiveHabitPlan else { return [] }
            return SupporterCommuteManager.upcomingAlternatives(in: plan, at: currentMinuteTick)
        }()

        Section {
            if isLoadingProactivePlan && proactiveHabitPlan == nil {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cerco soluzioni live...")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                        Text("\(formatCityOrStationSummary(slot.origins)) → \(formatCityOrStationSummary(slot.destinations))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            } else if let plan = proactiveHabitPlan, !upcomingAlternatives.isEmpty {
                let filteredPlan = PlanBReportDTO(
                    title: plan.title,
                    body: plan.body,
                    incident_type: plan.incident_type,
                    incident_detail: plan.incident_detail,
                    cancelled_train: plan.cancelled_train,
                    target_time: plan.target_time,
                    origins: plan.origins,
                    destinations: plan.destinations,
                    alternatives: upcomingAlternatives,
                    timestamp: plan.timestamp
                )

                ForEach(Array(upcomingAlternatives.prefix(2))) { alt in
                    proactiveAlternativeRow(alt: alt, plan: filteredPlan)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                followProactiveAlternative(alt)
                            } label: {
                                Label("Segui", systemImage: "location.viewfinder")
                            }
                            .tint(.blue)
                        }
                }

                if upcomingAlternatives.count > 2 {
                    Button {
                        Haptics.play(.light)
                        presentedPlanBSheet = TripsPlanBSheetItem(
                            plan: filteredPlan,
                            focusedAlternativeId: nil,
                            customTitle: "Viaggio abituale"
                        )
                    } label: {
                        HStack {
                            Text("Vedi tutte le opzioni (\(upcomingAlternatives.count))")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.accentColor)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                }
            } else {
                proactiveFallbackRow(for: slot)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            }
        } header: {
            Text(headerTitle)
        }
    }

    private func proactiveAlternativeRow(alt: PlanBAlternativeItem, plan: PlanBReportDTO) -> some View {
        let legs = alt.resolvedLegs
        let originDisplay = legs.first?.origin ?? alt.station
        let destDisplay = legs.last?.destination ?? alt.destination
        let depTime = legs.first?.departure_time ?? alt.departure_time
        let arrTime = legs.last?.arrival_time ?? alt.arrival_time ?? "--:--"
        let durationText = alt.duration ?? TrainManager.calculateDurationBetween(dep: depTime, arr: arrTime)
        let transfers = max(0, legs.count - 1)

        return HStack(spacing: 12) {
            Button {
                Haptics.play(.light)
                presentedPlanBSheet = TripsPlanBSheetItem(
                    plan: plan,
                    focusedAlternativeId: alt.id,
                    customTitle: "Viaggio abituale"
                )
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(originDisplay.compactStationName) → \(destDisplay.compactStationName)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text("\(depTime) → \(arrTime)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundColor(.blue)

                        if let durationText, !durationText.isEmpty {
                            Text("· \(durationText)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text(transfers == 0 ? "· Diretto" : "· \(transfers) camb\(transfers == 1 ? "io" : "i")")
                            .font(.caption)
                            .foregroundColor(transfers == 0 ? .green : .orange)

                        if alt.delay > 0 {
                            Text("+\(alt.delay)'")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundColor(alt.delay >= 15 ? .red : .orange)
                        }
                    }

                    if !alt.compactTrainsSummary.isEmpty {
                        Text(alt.compactTrainsSummary)
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
                followProactiveAlternative(alt)
            } label: {
                Text("Segui")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
        .padding(.vertical, 2)
    }

    private func proactiveFallbackRow(for slot: ActiveHabitCommuteSlot) -> some View {
        let originSummary = formatCityOrStationSummary(slot.origins)
        let destSummary = formatCityOrStationSummary(slot.destinations)

        return Button {
            Haptics.play(.light)
            Task {
                await loadProactiveHabitPlan(force: true)
                if let plan = proactiveHabitPlan {
                    presentedPlanBSheet = TripsPlanBSheetItem(
                        plan: plan,
                        focusedAlternativeId: nil,
                        customTitle: "Viaggio abituale"
                    )
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "map.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.green)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.isReturn ? "Ritorno abituale" : "Viaggio abituale")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Text("\(originSummary) → \(destSummary)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isLoadingProactivePlan {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func bannerPlanRow(_ plan: PlanBReportDTO) -> some View {
        let chosenAlt = plan.alternatives.first {
            $0.id == commuteManager.chosenAlternativeId ||
            commuteManager.chosenAlternativeId?.hasPrefix("\($0.train_number)_\($0.departure_time)") == true
        }
        let isDisruption = plan.incident_type != nil && plan.incident_type != "summary_ok"
        let originSummary = formatCityOrStationSummary(plan.origins)
        let destSummary = formatCityOrStationSummary(plan.destinations)

        return Button {
            Haptics.play(.light)
            presentedPlanBSheet = TripsPlanBSheetItem(
                plan: plan,
                focusedAlternativeId: commuteManager.chosenAlternativeId,
                customTitle: nil
            )
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isDisruption ? "exclamationmark.triangle.fill" : "map.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isDisruption ? .orange : .green)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    if let chosen = chosenAlt {
                        let cleanCat = cleanTrainCategory(chosen.category)
                        Text("\(cleanCat.isEmpty ? "" : "\(cleanCat) ")\(chosen.train_number) · \(chosen.departure_time)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text("da \(chosen.station.compactStationName) → \(chosen.destination.compactStationName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(plan.title.isEmpty ? (isDisruption ? "Piano B disponibile" : "Soluzione consigliata") : plan.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text("\(originSummary) → \(destSummary)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    // MARK: - Abitudini Section

    @ViewBuilder
    private var habitsSection: some View {
        let learnedRoutes = usageTracker.learnedHabitRoutes(excluding: manager.favoriteRoutes)

        Section {
            if learnedRoutes.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 22)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Apprendimento in corso")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                        Text("In Orario sta imparando le tue abitudini di viaggio. Appena avrà raccolto abbastanza spostamenti, ti proporrà qui suggerimenti personalizzati.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            } else {
                ForEach(learnedRoutes) { item in
                    HStack(spacing: 10) {
                        Button {
                            Haptics.play(.light)
                            selectedHabitRoute = item.route
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 22)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(item.route.originName.compactStationName) → \(item.route.destinationName.compactStationName)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Text("Consultata in \(item.distinctDays) giorni")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            Haptics.play(.medium)
                            withAnimation {
                                manager.toggleFavoriteRoute(
                                    originName: item.route.originName,
                                    originID: item.route.originID,
                                    destName: item.route.destinationName,
                                    destID: item.route.destinationID
                                )
                            }
                        } label: {
                            Image(systemName: "star")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .accessibilityLabel("Salva tra le tratte abituali")
                    }
                    .padding(.vertical, 3)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                }
            }
        } header: {
            Text("Abitudini")
        } footer: {
            Text("Puoi disattivare questa sezione in Impostazioni → Suggerimenti personalizzati.")
        }
    }

    // MARK: - Actions & Proactive Fetching

    private func toggleFollowSavedTrip(solution: TravelSolution, isCurrentlyFollowed: Bool) {
        Haptics.play(.medium)
        withAnimation {
            if isCurrentlyFollowed {
                commuteManager.stopFollowing(manager: manager)
            } else {
                if commuteManager.followedTrip != nil {
                    commuteManager.stopFollowing(manager: manager)
                }
                commuteManager.followSolution(solution)
            }
        }
    }

    private func followProactiveAlternative(_ alt: PlanBAlternativeItem) {
        Haptics.play(.medium)
        withAnimation {
            if commuteManager.followedTrip != nil {
                commuteManager.stopFollowing(manager: manager)
            }
            commuteManager.followAlternative(alt, legs: alt.resolvedLegs)
        }
    }

    private func loadProactiveHabitPlan(force: Bool) async {
        guard commuteManager.followedTrip == nil,
              commuteManager.homeBannerPlanB == nil,
              let slot = activeHabitSlot else {
            return
        }

        let key = proactiveTaskKey
        if !force && commuteManager.hasValidCachedProactiveHabitPlan(for: key) {
            return
        }

        isLoadingProactivePlan = true
        defer { isLoadingProactivePlan = false }

        let loc = await locationManager.getCurrentLocation(maxAge: 180)
        _ = await commuteManager.loadProactiveHabitPlanIfNeeded(
            for: slot,
            slotKey: key,
            userLat: loc?.coordinate.latitude,
            userLon: loc?.coordinate.longitude,
            force: force
        )
    }
}

struct PersonalRouteCardView: View {
    let route: FavoriteRoute

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.green)
                .frame(width: 22, alignment: .center)

            HStack(spacing: 6) {
                Text(route.effectiveOriginName.compactStationName)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Image(systemName: "arrow.left.and.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(route.effectiveDestinationName.compactStationName)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .minimumScaleFactor(0.85)

            Spacer(minLength: 4)
        }
        .padding(.vertical, 4)
    }
}

struct PersonalSavedTripCardView: View {
    let trip: SavedTrip
    let onOpenDetails: () -> Void

    var body: some View {
        Button(action: onOpenDetails) {
            HStack(spacing: 10) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.green)
                    .frame(width: 22, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(trip.origin.compactStationName)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(trip.destination.compactStationName)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                    .minimumScaleFactor(0.82)

                    HStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Text(trip.departureTime)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(trip.arrivalTime)
                        }
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundColor(.blue)
                        .fixedSize(horizontal: true, vertical: false)

                        Text("·")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        let transfers = max(0, trip.segments.count - 1)
                        Text(transfers == 0 ? "Diretto" : "\(transfers) camb\(transfers == 1 ? "io" : "i")")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(transfers == 0 ? .green : .orange)
                            .lineLimit(1)
                    }

                    if !trip.compactTrainsSummary.isEmpty {
                        Text(trip.compactTrainsSummary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
    }
}
