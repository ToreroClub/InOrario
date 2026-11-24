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
                                    .fill(Color.orange.opacity(0.12))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "star")
                                    .foregroundColor(.orange)
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
                                        .fill(Color.orange.opacity(0.12))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: "arrow.triangle.swap")
                                        .foregroundColor(.orange)
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                
                                HStack(spacing: 6) {
                                    Text(route.originName.formattedStationName)
                                        .font(.body)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Image(systemName: "arrow.right")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(route.destinationName.formattedStationName)
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
                                Label("Elimina", systemImage: "trash.fill")
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
                                    .fill(Color.blue.opacity(0.12))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "bookmark")
                                    .foregroundColor(.blue)
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
                                        .fill(Color.blue.opacity(0.12))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: "tram.fill")
                                        .foregroundColor(.blue)
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
                                Label("Elimina", systemImage: "trash.fill")
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
    
    @State private var isReversed = false
    @State private var hasSearched = false
    
    private var currentOriginID: String { isReversed ? route.destinationID : route.originID }
    private var currentOriginName: String { isReversed ? route.destinationName : route.originName }
    private var currentDestID: String { isReversed ? route.originID : route.destinationID }
    private var currentDestName: String { isReversed ? route.originName : route.destinationName }
    
    var body: some View {
        VStack(spacing: 0) {
            if manager.isSearchingSolutions {
                Spacer()
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Ricerca soluzioni live in corso...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List {
                    Section {
                        if manager.travelSolutions.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "train.side.front.car")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                Text("Nessun treno trovato al momento")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("Riprova a caricare tra qualche minuto o controlla lo stato della linea.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            .padding(.vertical, 40)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                        } else {
                            ForEach(manager.travelSolutions) { solution in
                                NavigationLink(destination: TravelSolutionDetailsView(solution: solution)) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text("\(solution.category) \(solution.trainNumber)")
                                                .font(.headline)
                                            Spacer()
                                            Text(solution.duration)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                        HStack {
                                            Text(solution.departureTime)
                                                .fontWeight(.bold)
                                                .foregroundColor(.blue)
                                            Image(systemName: "arrow.right")
                                                .foregroundColor(.secondary)
                                                .font(.caption)
                                            Text(solution.arrivalTime)
                                                .fontWeight(.bold)
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                }
                                .contextMenu {
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
                            Button {
                                Haptics.play(.medium)
                                isReversed.toggle()
                                Task {
                                    await loadSolutions()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.left.arrow.right")
                                    Text("Inverti")
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("\(currentOriginName.replacingOccurrences(of: "Milano ", with: "")) ➔ \(currentDestName.replacingOccurrences(of: "Milano ", with: ""))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    Haptics.play(.medium)
                    Task {
                        await loadSolutions()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(manager.isSearchingSolutions)
            }
        }
        .task {
            await loadSolutions()
            hasSearched = true
        }
    }
    
    private func loadSolutions() async {
        await manager.searchTravelSolutions(
            originID: currentOriginID,
            destID: currentDestID,
            date: Date(),
            originName: currentOriginName,
            destName: currentDestName,
            source: .favoriteRoute
        )
        usageTracker.recordRouteSearch(originID: currentOriginID, originName: currentOriginName, destID: currentDestID, destName: currentDestName, location: locationManager.userLocation?.coordinate)
    }
}
