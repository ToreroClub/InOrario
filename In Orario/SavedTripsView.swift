import SwiftUI
import CoreLocation

struct SavedTripsView: View {
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var usageTracker: UsageTracker
    @EnvironmentObject var locationManager: LocationManager
    @Environment(\.dismiss) var dismiss
    
    @State private var originName = ""
    @State private var originID = ""
    @State private var destName = ""
    @State private var destID = ""
    @State private var searchDate = Date()
    
    @State private var showOriginSearch = false
    @State private var showDestSearch = false
    @State private var showSearchFields = false
    
    var body: some View {
        List {
            // SEZIONE DI RICERCA VIAGGI ESPANDIBILE
            Section {
                DisclosureGroup(isExpanded: $showSearchFields) {
                    VStack(spacing: 12) {
                        Button(action: { showOriginSearch = true }) {
                            HStack {
                                Image(systemName: "circle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption2)
                                Text(originName.isEmpty ? "Stazione di Partenza" : originName)
                                    .fontWeight(originName.isEmpty ? .regular : .semibold)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                        }
                        .foregroundColor(.primary)
                        .buttonStyle(BorderlessButtonStyle())
                        .sheet(isPresented: $showOriginSearch) {
                            StationSelectionSheet(selectedName: $originName, selectedID: $originID, title: "Partenza")
                        }
                        
                        Button(action: { showDestSearch = true }) {
                            HStack {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.subheadline)
                                Text(destName.isEmpty ? "Stazione di Arrivo" : destName)
                                    .fontWeight(destName.isEmpty ? .regular : .semibold)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                        }
                        .foregroundColor(.primary)
                        .buttonStyle(BorderlessButtonStyle())
                        .sheet(isPresented: $showDestSearch) {
                            StationSelectionSheet(selectedName: $destName, selectedID: $destID, title: "Arrivo")
                        }
                        
                        DatePicker("Data e Ora", selection: $searchDate, displayedComponents: [.date, .hourAndMinute])
                            .environment(\.locale, Locale(identifier: "it_IT"))
                            .padding(.horizontal, 4)
                        
                        Button(action: {
                            Task {
                                Haptics.play(.medium)
                                await manager.searchTravelSolutions(originID: originID, destID: destID, date: searchDate)
                                usageTracker.recordRouteSearch(originID: originID, originName: originName, destID: destID, destName: destName, location: locationManager.userLocation?.coordinate)
                            }
                        }) {
                            HStack {
                                Spacer()
                                if manager.isSearchingSolutions {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Cerca Soluzioni")
                                        .fontWeight(.bold)
                                }
                                Spacer()
                            }
                            .padding()
                            .background(originID.isEmpty || destID.isEmpty || originID == destID ? Color.gray : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .disabled(originID.isEmpty || destID.isEmpty || originID == destID || manager.isSearchingSolutions)
                        
                        if !originID.isEmpty && !destID.isEmpty && originID != destID {
                            Button(action: {
                                manager.toggleFavoriteRoute(originName: originName, originID: originID, destName: destName, destID: destID)
                                Haptics.play(.medium)
                            }) {
                                HStack {
                                    Image(systemName: manager.isFavoriteRoute(originID: originID, destID: destID) ? "star.fill" : "star")
                                        .foregroundColor(manager.isFavoriteRoute(originID: originID, destID: destID) ? .yellow : .blue)
                                    Text(manager.isFavoriteRoute(originID: originID, destID: destID) ? "Rimuovi dai Preferiti" : "Salva Tratta nei Preferiti")
                                }
                                .font(.subheadline)
                                .padding(.top, 4)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                    .padding(.vertical, 8)
                } label: {
                    Label("Pianifica un Viaggio", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.headline)
                        .foregroundColor(.blue)
                }
            }
            
            // RISULTATI DELLA RICERCA LIVE
            if manager.isSearchingSolutions {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Ricerca soluzioni live in corso...").font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                }
            } else if !manager.travelSolutions.isEmpty {
                Section(header: Text("Soluzioni Trovate")) {
                    ForEach(manager.travelSolutions) { solution in
                        NavigationLink(destination: TravelSolutionDetailsView(solution: solution)) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("\(solution.category) \(solution.trainNumber)").font(.headline)
                                    Spacer()
                                    Text(solution.duration).font(.subheadline).foregroundColor(.secondary)
                                }
                                HStack {
                                    Text(solution.departureTime).fontWeight(.bold).foregroundColor(.blue)
                                    Image(systemName: "arrow.right").foregroundColor(.secondary).font(.caption)
                                    Text(solution.arrivalTime).fontWeight(.bold).foregroundColor(.blue)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            
            // LE MIE TRATTE PREFERITE GENERALI
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
            
            // CORSE SINGOLE SALVATE
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
            
            if manager.favoriteRoutes.isEmpty && manager.savedTrips.isEmpty && manager.travelSolutions.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "signpost.right.and.left")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    Text("Nessun preferito salvato")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Configura le tue tratte preferite generiche o pianifica un viaggio qui sopra.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                }
                .padding(.top, 40)
                .listRowBackground(Color.clear)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("Viaggi e Tratte")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            manager.travelSolutions = []
        }
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
