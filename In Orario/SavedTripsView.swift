import SwiftUI

struct SavedTripsView: View {
    @EnvironmentObject var manager: TrainManager
    
    var body: some View {
        List {
            if manager.favoriteRoutes.isEmpty && manager.savedTrips.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "bookmark.slash")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    Text("Nessun preferito salvato")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Configura le tue tratte preferite generiche o salva singole corse di viaggio per vederle qui.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 50)
                .listRowBackground(Color.clear)
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                if !manager.favoriteRoutes.isEmpty {
                    Section(header: Text("Le Mie Tratte Preferite")) {
                        ForEach(manager.favoriteRoutes) { route in
                            NavigationLink(destination: FavoriteRouteSolutionView(route: route)) {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color.orange.opacity(0.12))
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            Image(systemName: "star.fill")
                                                .foregroundColor(.orange)
                                                .font(.subheadline)
                                        )
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(route.originName) ➔ \(route.destinationName)")
                                            .font(.headline)
                                        Text("Tocca per cercare le partenze reali")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Haptics.play(.medium)
                                    manager.toggleFavoriteRoute(originName: route.originName, originID: route.originID, destName: route.destinationName, destID: route.destinationID)
                                } label: {
                                    Label("Rimuovi", systemImage: "trash.fill")
                                }
                            }
                        }
                    }
                }
                
                if !manager.savedTrips.isEmpty {
                    Section(header: Text("Corse Singole Salvate")) {
                        ForEach(manager.savedTrips) { trip in
                            let sol = trip.asTravelSolution
                            NavigationLink(destination: TravelSolutionDetailsView(solution: sol)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(trip.origin) - \(trip.destination)").font(.headline)
                                    HStack {
                                        Text(trip.departureTime).fontWeight(.bold).foregroundColor(.blue)
                                        Image(systemName: "arrow.right").foregroundColor(.secondary).font(.caption)
                                        Text(trip.arrivalTime).fontWeight(.bold).foregroundColor(.blue)
                                        Spacer()
                                        Text(trip.duration).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    manager.toggleSavedTrip(solution: sol)
                                } label: {
                                    Label("Rimuovi", systemImage: "trash.fill")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Viaggi Salvati")
        .navigationBarTitleDisplayMode(.large)
    }
}

struct FavoriteRouteSolutionView: View {
    @EnvironmentObject var manager: TrainManager
    let route: FavoriteRoute
    
    @State private var hasSearched = false
    
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
                    Section(header: Text("Partenze in tempo reale")) {
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
                                            Text(solution.departureTime).fontWeight(.bold).foregroundColor(.blue)
                                            Image(systemName: "arrow.right").foregroundColor(.secondary).font(.caption)
                                            Text(solution.arrivalTime).fontWeight(.bold).foregroundColor(.blue)
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
                    }
                }
            }
        }
        .navigationTitle("\(route.originName.replacingOccurrences(of: "Milano ", with: "")) ➔ \(route.destinationName.replacingOccurrences(of: "Milano ", with: ""))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    Haptics.play(.medium)
                    Task {
                        await manager.searchTravelSolutions(originID: route.originID, destID: route.destinationID, date: Date())
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(manager.isSearchingSolutions)
            }
        }
        .task {
            await manager.searchTravelSolutions(originID: route.originID, destID: route.destinationID, date: Date())
            hasSearched = true
        }
    }
}
