import SwiftUI
import CoreLocation

struct SavedTripsView: View {
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var usageTracker: UsageTracker
    @EnvironmentObject var locationManager: LocationManager
    @Environment(\.dismiss) var dismiss
    
    @State private var showSearchSheet = false
    
    var body: some View {
        List {
            // SEZIONE 1: TRATTE ABITUALI
            Section {
                if manager.favoriteRoutes.isEmpty {
                    Button {
                        showSearchSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.green.opacity(0.12))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "arrow.left.arrow.right")
                                    .foregroundColor(.green)
                                    .font(.system(size: 15))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Nessuna tratta salvata")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Text("Cerca un viaggio e tocca ★ per salvare la tratta.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "magnifyingglass")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    ForEach(manager.favoriteRoutes) { route in
                        NavigationLink(destination: FavoriteRouteSolutionView(route: route)) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.green.opacity(0.12))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: "arrow.left.arrow.right")
                                        .foregroundColor(.green)
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                
                                HStack(spacing: 6) {
                                    Text(route.effectiveOriginName.formattedStationName)
                                        .font(.body)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Image(systemName: "arrow.right")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(route.effectiveDestinationName.formattedStationName)
                                        .font(.body)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Haptics.play(.medium)
                                manager.toggleFavoriteRoute(originName: route.originName, originID: route.originID, destName: route.destinationName, destID: route.destinationID)
                            } label: {
                                Label("Rimuovi dai preferiti", systemImage: "star.slash.fill")
                            }
                        }
                    }
                }
            } header: {
                Text("Tratte Abituali")
            } footer: {
                Text(manager.favoriteRoutes.isEmpty
                     ? "Una tratta è un percorso tra due stazioni: salvala per consultare con un tocco tutte le partenze disponibili."
                     : "Tocca una tratta per vedere tutte le partenze disponibili.")
            }
            
            // SEZIONE 2: VIAGGI SALVATI
            Section {
                if manager.savedTrips.isEmpty {
                    Button {
                        showSearchSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.green.opacity(0.12))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "bookmark.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 15))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Nessun viaggio salvato")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Text("Salva un itinerario a un orario specifico per monitorare treni, coincidenze e ritardi.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "magnifyingglass")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    ForEach(manager.savedTrips) { trip in
                        let sol = trip.asTravelSolution
                        NavigationLink(destination: TravelSolutionDetailsView(solution: sol)) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.green.opacity(0.12))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: "bookmark.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 15))
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("\(trip.origin.formattedStationName) ➔ \(trip.destination.formattedStationName)")
                                            .font(.body)
                                            .fontWeight(.semibold)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(trip.duration)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    HStack(spacing: 8) {
                                        HStack(spacing: 4) {
                                            Text(trip.departureTime)
                                                .font(.subheadline)
                                                .fontWeight(.bold)
                                                .foregroundColor(.blue)
                                                .lineLimit(1)
                                            Image(systemName: "arrow.right")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            Text(trip.arrivalTime)
                                                .font(.subheadline)
                                                .fontWeight(.bold)
                                                .foregroundColor(.blue)
                                                .lineLimit(1)
                                        }
                                        .fixedSize(horizontal: true, vertical: false)
                                        .layoutPriority(1)
                                        
                                        let compactSummary = trip.compactTrainsSummary
                                        if !compactSummary.isEmpty {
                                            Text("•")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(compactSummary)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Haptics.play(.medium)
                                manager.toggleSavedTrip(solution: sol)
                            } label: {
                                Label("Rimuovi dai preferiti", systemImage: "star.slash.fill")
                            }
                        }
                    }
                }
            } header: {
                Text("Viaggi Salvati")
            } footer: {
                Text(manager.savedTrips.isEmpty
                     ? "Un viaggio è un itinerario a un orario specifico, composto da uno o più mezzi: salvalo per monitorare coincidenze, fermate e ritardi."
                     : "Tocca un viaggio per controllare lo stato dei treni, le coincidenze e le fermate.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Viaggi e Tratte")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Chiudi") {
                    dismiss()
                }
                .fontWeight(.bold)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSearchSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showSearchSheet) {
            TravelSearchView()
                .environmentObject(manager)
                .environmentObject(locationManager)
        }
    }
}

// MARK: - Monitoraggio Soluzioni Live per Tratta Abituale
struct FavoriteRouteSolutionView: View {
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var usageTracker: UsageTracker
    @EnvironmentObject var locationManager: LocationManager
    let route: FavoriteRoute
    
    @State private var isReversed: Bool
    @State private var selectedDate: Date = Date()
    @State private var hasSearched = false
    @State private var dateReloadTask: Task<Void, Never>? = nil

    init(route: FavoriteRoute, initialReversed: Bool? = nil) {
        self.route = route
        _isReversed = State(initialValue: initialReversed ?? route.effectiveIsReversed)
    }
    
    private var currentOriginID: String { isReversed ? route.destinationID : route.originID }
    private var currentOriginName: String { isReversed ? route.destinationName : route.originName }
    private var currentDestID: String { isReversed ? route.originID : route.destinationID }
    private var currentDestName: String { isReversed ? route.originName : route.destinationName }
    
    var body: some View {
        List {
            // Controlli in alto: Data, Ora (24h italiano) e Inverti tratta
            Section {
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        DatePicker("", selection: $selectedDate, displayedComponents: .date)
                            .labelsHidden()
                            .environment(\.locale, SharedFormatters.italian24HourLocale)
                            .environment(\.timeZone, TimeZone(identifier: "Europe/Rome") ?? .current)
                        Italian24HourTimePicker(selection: $selectedDate)
                    }
                    .transaction { $0.animation = nil }

                    Spacer(minLength: 4)

                    Button {
                        Haptics.play(.medium)
                        isReversed.toggle()
                        manager.setFavoriteRouteReversed(routeID: route.id, isReversed: isReversed)
                        Task {
                            await loadSolutions(forceRefresh: false)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.caption.weight(.bold))
                            Text("Inverti")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(manager.isSearchingSolutions)
                }
                .padding(.vertical, 2)
            }

            Section {
                if manager.isSearchingSolutions {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.1)
                            Text("Ricerca soluzioni live in corso...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 28)
                    .listRowBackground(Color.clear)
                } else if manager.travelSolutions.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "tram.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.gray)
                        Text("Nessun treno trovato al momento")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Prova a cambiare orario o aggiorna tra qualche minuto.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(manager.travelSolutions) { solution in
                        let isSaved = manager.isTripSaved(solution: solution)
                        let transfers = max(0, solution.segments.count - 1)
                        NavigationLink(destination: TravelSolutionDetailsView(solution: solution)) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text("\(solution.category) \(solution.trainNumber)")
                                        .font(.headline)
                                        .lineLimit(1)
                                    if isSaved {
                                        Image(systemName: "bookmark.fill")
                                            .font(.caption2)
                                            .foregroundColor(.green)
                                    }
                                    Spacer()
                                    Text(transfers == 0 ? "Diretto" : "\(transfers) camb\(transfers == 1 ? "io" : "i")")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(transfers == 0 ? .green : .orange)
                                }
                                HStack(spacing: 6) {
                                    HStack(spacing: 4) {
                                        Text(solution.departureTime)
                                        Image(systemName: "arrow.right")
                                            .foregroundColor(.secondary)
                                            .font(.caption2)
                                        Text(solution.arrivalTime)
                                    }
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundColor(.blue)
                                    Spacer()
                                    Text(solution.duration)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                Haptics.play(.medium)
                                withAnimation {
                                    manager.toggleSavedTrip(solution: solution)
                                }
                            } label: {
                                Label(
                                    isSaved ? "Rimuovi dai salvati" : "Salva viaggio",
                                    systemImage: isSaved ? "star.slash.fill" : "bookmark.fill"
                                )
                            }
                            .tint(isSaved ? .red : .green)
                        }
                        .contextMenu {
                            Button {
                                Haptics.play(.medium)
                                withAnimation {
                                    manager.toggleSavedTrip(solution: solution)
                                }
                            } label: {
                                Label(
                                    isSaved ? "Rimuovi viaggio salvato" : "Salva viaggio",
                                    systemImage: isSaved ? "star.slash.fill" : "bookmark.fill"
                                )
                            }

                            let validSegments = solution.segments.filter { $0.trainCategory != "Trasporto Urbano" && !$0.trainNumber.isEmpty }
                            if !validSegments.isEmpty {
                                ForEach(validSegments) { segment in
                                    Button(action: {
                                        let desc = "\(segment.origin) - \(segment.destination)"
                                        manager.toggleFavorite(trainNumber: segment.trainNumber, description: desc, departureTime: segment.departureTime)
                                        Haptics.play(.medium)
                                    }) {
                                        let isFav = manager.favoriteTrains.contains(where: { $0.number == segment.trainNumber })
                                        Label(
                                            isFav ? "Rimuovi \(segment.trainCategory) \(segment.trainNumber) dai Preferiti" : "Aggiungi \(segment.trainCategory) \(segment.trainNumber) ai Preferiti",
                                            systemImage: isFav ? "star.slash.fill" : "star.fill"
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Partenze disponibili")
                    Spacer()
                    if let updated = manager.lastTravelSolutionsFetchedAt, !manager.isSearchingSolutions, !manager.travelSolutions.isEmpty {
                        Text("Agg. \(SharedFormatters.time.string(from: updated))")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("\(currentOriginName.compactStationName) → \(currentDestName.compactStationName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    Haptics.play(.medium)
                    Task {
                        await loadSolutions(forceRefresh: true)
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(manager.isSearchingSolutions)
            }
        }
        .refreshable {
            await loadSolutions(forceRefresh: true)
        }
        .onChange(of: selectedDate) { _, _ in
            guard hasSearched else { return }
            dateReloadTask?.cancel()
            dateReloadTask = Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                await loadSolutions(forceRefresh: false)
            }
        }
        .onDisappear {
            dateReloadTask?.cancel()
            dateReloadTask = nil
        }
        .task {
            await loadSolutions(forceRefresh: false)
            hasSearched = true
        }
    }
    
    private func loadSolutions(forceRefresh: Bool) async {
        await manager.searchTravelSolutions(
            originID: currentOriginID,
            destID: currentDestID,
            date: selectedDate,
            originName: currentOriginName,
            destName: currentDestName,
            source: .favoriteRoute,
            forceRefresh: forceRefresh
        )
        usageTracker.recordRouteSearch(originID: currentOriginID, originName: currentOriginName, destID: currentDestID, destName: currentDestName, location: locationManager.userLocation?.coordinate)
        UserInterestTelemetryManager.shared.recordRouteUsage(
            originName: currentOriginName,
            originID: currentOriginID,
            destinationName: currentDestName,
            destinationID: currentDestID
        )
    }
}
