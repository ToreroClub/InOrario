import SwiftUI
import Combine
import Foundation
import CoreLocation
import ActivityKit

struct LiveTrainBand: View {
    @EnvironmentObject var manager: TrainManager
    let segment: TravelSegment
    
    @State private var isExpanded = false
    @State private var liveStatus: StopsResult?
    @State private var isLoading = false
    @State private var showClassicStops = false
    @State private var metroDetails: (line: String, headsign: String, mins: Int, dep: String, arr: String)? = nil
    @State private var isLoadingMetro = false
    
    private var isWalk: Bool {
        segment.isStationWalk || segment.trainCategory == "Interscambio a piedi"
    }
    
    private var isUrban: Bool {
        segment.trainCategory == "Trasporto Urbano" || segment.trainCategory.contains("Metro")
    }
    
    private var bandLabel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if isWalk {
                    Image(systemName: "figure.walk")
                        .foregroundColor(.orange)
                    Text("Interscambio a piedi")
                        .font(.headline)
                        .foregroundColor(.primary)
                } else if isUrban {
                    Image(systemName: "tram.fill")
                        .foregroundColor(.purple)
                    let titleText: String = {
                        if let metro = metroDetails {
                            return "Metro \(metro.line)"
                        } else if segment.trainCategory.contains("Metro") {
                            return segment.trainCategory
                        } else {
                            return "\(segment.trainCategory) \(segment.trainNumber)"
                        }
                    }()
                    Text(titleText)
                        .font(.headline)
                        .foregroundColor(.primary)
                } else {
                    Image(systemName: "tram.fill")
                        .foregroundColor(.blue)
                    Text("\(segment.trainCategory) \(segment.trainNumber)")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                if isWalk {
                    Text("\(segment.travelMinutes ?? 1) min a piedi")
                        .font(.caption.bold())
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.18))
                        .cornerRadius(4)
                } else if isUrban {
                    let mins = metroDetails?.mins ?? segment.travelMinutes
                    if let m = mins {
                        Text("\(m) min stimati")
                            .font(.caption.bold())
                            .foregroundColor(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.18))
                            .cornerRadius(4)
                    } else if isLoadingMetro {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Text("15 min stimati")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if isLoading {
                    ProgressView().scaleEffect(0.8)
                } else if let res = liveStatus, res.errorMessage == nil {
                    let delayStr = res.status.statusMessage
                    Text(delayStr)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(delayStr.contains("orario") || delayStr.contains("viaggio") || delayStr.contains("attesa") ? .green : .red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((delayStr.contains("orario") || delayStr.contains("viaggio") || delayStr.contains("attesa") ? Color.green : Color.red).opacity(0.2))
                        .cornerRadius(4)
                }
            }
            
            HStack {
                VStack(alignment: .leading) {
                    Text(String(format: String(localized: "Da: %@"), segment.origin)).font(.subheadline)
                    Text(String(format: String(localized: "A: %@"), segment.destination)).font(.subheadline)
                    let headsign = metroDetails?.headsign ?? segment.urbanHeadsign
                    if let h = headsign, !h.isEmpty {
                        Text("Dir. \(h)")
                            .font(.caption.bold())
                            .foregroundColor(.purple)
                    }
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(metroDetails?.dep ?? segment.departureTime).font(.subheadline).fontWeight(.bold)
                    Text(metroDetails?.arr ?? segment.arrivalTime).font(.subheadline).fontWeight(.bold)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    var body: some View {
        Group {
            if isWalk || isUrban {
                bandLabel
            } else {
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        if isLoading {
                            HStack { Spacer(); ProgressView(); Spacer() }
                        } else if let res = liveStatus {
                            if let err = res.errorMessage {
                                Text(err).font(.caption).foregroundColor(.red)
                            } else {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(res.status.statusMessage).font(.subheadline).bold().foregroundColor(.secondary)
                                    if res.status.lastStation != "--" {
                                        Text(String(format: String(localized: "Ultimo rilevamento: %@ alle %@"), res.status.lastStation, res.status.lastTime)).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                
                                Divider()
                                
                                ForEach(res.stops) { stop in
                                    HStack {
                                        Circle().fill(stop.delay > 0 ? Color.red : Color.green).frame(width: 8, height: 8)
                                        Text(stop.stationName).font(.caption)
                                        Spacer()
                                        Text(stop.actualTime ?? stop.time).font(.caption).bold()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    bandLabel
                }
            }
        }
        .contextMenu {
            if !isUrban && !isWalk && !segment.trainNumber.isEmpty {
                Button(action: {
                    showClassicStops = true
                    Haptics.play(.medium)
                }) {
                    Label("Vista dettagli", systemImage: "tram.fill")
                }
                
                Button(action: {
                    withAnimation {
                        isExpanded.toggle()
                    }
                    Haptics.play(.light)
                }) {
                    Label(isExpanded ? "Comprimi fermate" : "Espandi fermate", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                }
                
                Button(action: {
                    let desc = "\(segment.origin) - \(segment.destination)"
                    manager.toggleFavorite(trainNumber: segment.trainNumber, description: desc, departureTime: segment.departureTime)
                    Haptics.play(.medium)
                }) {
                    let isFav = manager.favoriteTrains.contains(where: { $0.number == segment.trainNumber })
                    Label(isFav ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti", systemImage: isFav ? "star.slash.fill" : "star.fill")
                }
            }
        }
        .sheet(isPresented: $showClassicStops) {
            let dummy = Train(
                category: segment.trainCategory,
                number: segment.trainNumber,
                destination: segment.destination,
                time: segment.departureTime,
                delay: "",
                platform: ""
            )
            NavigationStack {
                TrainStopsView(train: dummy, showCloseButton: true)
                    .environmentObject(manager)
            }
        }
        .task {
            if isUrban {
                if metroDetails == nil {
                    if let mins = segment.travelMinutes {
                        let line = segment.trainCategory.replacingOccurrences(of: "Metro ", with: "")
                        let headsign = segment.urbanHeadsign ?? ""
                        metroDetails = (line: line, headsign: headsign, mins: mins, dep: segment.departureTime, arr: segment.arrivalTime)
                    } else {
                        isLoadingMetro = true
                        metroDetails = await manager.resolveUrbanLeg(orig: segment.origin, dest: segment.destination, time: segment.departureTime)
                        isLoadingMetro = false
                    }
                }
            } else if !isWalk {
                if liveStatus == nil {
                    isLoading = true
                    liveStatus = await manager.fetchLiveStops(for: segment.trainNumber)
                    isLoading = false
                }
            }
        }
    }
}

struct TravelSolutionDetailsView: View {
    @EnvironmentObject var manager: TrainManager
    @ObservedObject private var commuteManager = SupporterCommuteManager.shared
    @Environment(\.dismiss) private var dismiss
    let solution: TravelSolution
    var showCloseButton: Bool = false
    
    var passanteDirectAdvice: String? {
        let segs = solution.segments
        guard segs.count >= 2 else { return nil }
        
        let first = segs[0]
        let isFirstSuburban = first.trainCategory.contains("Suburbano") || first.trainNumber.hasPrefix("S") || first.trainCategory == "S" || first.trainCategory.uppercased().contains("S5") || first.trainCategory.uppercased().contains("S6")
        let firstDestClean = first.destination.uppercased()
        let isRhoFiera = firstDestClean.contains("RHO") && firstDestClean.contains("FIERA")
        
        if isFirstSuburban && isRhoFiera {
            let hasUrbanLater = segs.contains { $0.trainCategory.contains("Metro") || $0.trainCategory == "Trasporto Urbano" }
            let arrivesAtGaribaldiOrCentrale = segs.contains { $0.destination.uppercased().contains("GARIBALDI") || $0.destination.uppercased().contains("CENTRALE") }
            
            if hasUrbanLater || arrivesAtGaribaldiOrCentrale {
                return "Puoi rimanere a bordo del treno \(first.trainNumber) senza scendere a Rho-Fiera! Il treno prosegue direttamente nel Passante Ferroviario fermando a Milano Porta Garibaldi Passante, Repubblica, Porta Venezia e Dateo."
            }
        }
        return nil
    }
    
    var body: some View {
        List {
            if let tip = passanteDirectAdvice {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lightbulb.max.fill")
                            .font(.title3)
                            .foregroundColor(.yellow)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Consiglio: evita il cambio a Rho-Fiera")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            Text(tip)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section {
                VStack(alignment: .center, spacing: 8) {
                    HStack {
                        VStack {
                            Text(solution.origin).font(.headline).multilineTextAlignment(.center)
                            Text(solution.departureTime).font(.title2).fontWeight(.bold)
                        }
                        Spacer()
                        VStack {
                            Image(systemName: "arrow.right").font(.title2).foregroundColor(.gray)
                            Text(solution.duration).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack {
                            Text(solution.destination).font(.headline).multilineTextAlignment(.center)
                            Text(solution.arrivalTime).font(.title2).fontWeight(.bold)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            
            Section {
                if solution.segments.isEmpty {
                    Text("Nessun dettaglio treni disponibile.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(solution.segments) { segment in
                        LiveTrainBand(segment: segment)
                    }
                }
            } header: {
                Text("Treni del Viaggio")
            } footer: {
                Text("Tieni premuto su un treno per aggiungere ai preferiti o saperne di più.\n\n\"Salva per dopo\" per ritrovarlo nei Viaggi in alto a destra. \"Segui ora\" per continuare a visualizzare il tuo percorso dalla Home.")
            }
        }
        .navigationTitle("Dettagli Viaggio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showCloseButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(.tertiarySystemFill))
                                .frame(width: 30, height: 30)
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Chiudi")
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                let isSaved = manager.isTripSaved(solution: solution)
                let isFollowed = commuteManager.isSolutionFollowed(solution)
                Menu {
                    Button(role: isFollowed ? .destructive : nil) {
                        Haptics.play(.medium)
                        withAnimation {
                            if isFollowed {
                                commuteManager.stopFollowing(manager: manager)
                            } else {
                                if commuteManager.followedTrip != nil {
                                    commuteManager.stopFollowing(manager: manager)
                                }
                                commuteManager.followSolution(solution)
                            }
                        }
                    } label: {
                        Label(
                            isFollowed ? "Smetti di seguire" : "Segui ora",
                            systemImage: isFollowed ? "xmark.circle" : "location.fill"
                        )
                    }
                    
                    Button {
                        Haptics.play(.medium)
                        withAnimation {
                            manager.toggleSavedTrip(solution: solution)
                        }
                    } label: {
                        Label(
                            isSaved ? "Rimuovi dai Viaggi" : "Salva per dopo",
                            systemImage: isSaved ? "bookmark.slash.fill" : "bookmark.fill"
                        )
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isFollowed ? "checkmark.circle.fill" : (isSaved ? "bookmark.fill" : "bookmark"))
                        Text(isFollowed ? "Seguito" : (isSaved ? "Salvato" : "Salva"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(isFollowed ? .orange : (isSaved ? .green : .blue))
                }
            }
        }
        .onAppear {
            manager.addRecentViewedTrip(solution: solution)
        }
    }
}

struct StationSelectionSheet: View {
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var locationManager: LocationManager
    @Environment(\.dismiss) var dismiss
    @Binding var selectedName: String
    @Binding var selectedID: String
    var onStationSelected: ((Station) -> Void)? = nil
    @State private var query = ""
    let title: String
    var autoFocusSearch: Bool = true
    
    @FocusState private var isSearchFocused: Bool
    @State private var resolvingStationName: String? = nil
    @State private var searchTask: Task<Void, Never>? = nil
    
    var nearbyStations: [(name: String, distanceText: String)] {
        guard let userLoc = locationManager.userLocation else { return [] }
        let sorted = manager.allRFIStations.compactMap { st -> (name: String, dist: Double)? in
            guard let lat = st.lat, let lon = st.lon else { return nil }
            let stLoc = CLLocation(latitude: lat, longitude: lon)
            let d = userLoc.distance(from: stLoc)
            return (st.name, d)
        }
        .sorted { $0.dist < $1.dist }
        
        var seen = Set<String>()
        var result: [(name: String, distanceText: String)] = []
        for item in sorted {
            let clean = item.name.formattedStationName
            let lower = clean.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !seen.contains(lower) {
                seen.insert(lower)
                let distStr = item.dist < 1000 ? "\(Int(item.dist))m" : String(format: "%.1fkm", item.dist / 1000.0)
                result.append((name: clean, distanceText: distStr))
                if result.count == 3 { break }
            }
        }
        return result
    }
    
    private var recentStations: [VTSearchStation] {
        Array(manager.unifiedRecentStations.prefix(4))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Barra di ricerca nativa iOS stile capsula con focus automatico
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16, weight: .medium))
                    
                    TextField("Cerca stazione...", text: $query)
                        .font(.system(size: 16))
                        .focused($isSearchFocused)
                        .submitLabel(.search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemFill))
                .clipShape(Capsule())
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .background(Color(.systemGroupedBackground))
                
                List {
                    if manager.isSearching {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .listRowBackground(Color.clear)
                    } else if !query.isEmpty {
                        if manager.searchTrenitaliaLocations.isEmpty {
                            Text("Nessuna stazione trovata per \"\(query)\".")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                                .padding(.vertical, 8)
                        } else {
                            Section(header: Text("Risultati Ricerca")) {
                                ForEach(manager.searchTrenitaliaLocations) { result in
                                    Button {
                                        let resolved = manager.resolveStation(name: result.name)
                                        selectedName = resolved.name.formattedStationName
                                        selectedID = String(result.id)
                                        let vt = resolved.vtID ?? manager.getVtID(for: resolved.name) ?? ""
                                        manager.addToRecentStations(VTSearchStation(nomeLungo: resolved.name, nomeBreve: resolved.name, vtID: vt))
                                        manager.addToViewedRecentStations(name: resolved.name, vtID: vt)
                                        onStationSelected?(resolved)
                                        Haptics.play(.medium)
                                        dismiss()
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "building.2.crop.circle.fill")
                                                .foregroundColor(.blue)
                                                .font(.title3)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(result.name.formattedStationName)
                                                    .font(.headline)
                                                    .foregroundColor(.primary)
                                                if !result.displayName.isEmpty && result.displayName != result.name {
                                                    Text(result.displayName)
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            Spacer()
                                            if selectedID == String(result.id) {
                                                Image(systemName: "checkmark")
                                                    .foregroundColor(.blue)
                                                    .fontWeight(.bold)
                                            }
                                        }
                                        .padding(.vertical, 3)
                                    }
                                }
                            }
                        }
                    } else {
                        // Empty query: show Nearby & Recent
                        if !nearbyStations.isEmpty {
                            Section(header: Text("Stazioni Vicine")) {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(nearbyStations.prefix(3), id: \.name) { st in
                                            Button {
                                                selectStationByName(st.name)
                                            } label: {
                                                HStack(spacing: 6) {
                                                    if resolvingStationName == st.name {
                                                        ProgressView()
                                                            .scaleEffect(0.7)
                                                    } else {
                                                        Image(systemName: "location.fill")
                                                            .font(.system(size: 11, weight: .bold))
                                                            .foregroundColor(.blue)
                                                    }
                                                    
                                                    Text(st.name)
                                                        .font(.subheadline.weight(.semibold))
                                                        .foregroundColor(.primary)
                                                    
                                                    Text(st.distanceText)
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(Color(.secondarySystemGroupedBackground))
                                                .clipShape(Capsule())
                                                .overlay(
                                                    Capsule()
                                                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                                                )
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            .disabled(resolvingStationName != nil)
                                        }
                                    }
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                }
                                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 4, trailing: 0))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        } else if locationManager.authorizationStatus == .notDetermined {
                            Section {
                                Button {
                                    locationManager.requestAuthorization()
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "location.circle")
                                            .foregroundColor(.blue)
                                        Text("Abilita posizione per stazioni vicine")
                                            .font(.subheadline)
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                        
                        if !recentStations.isEmpty {
                            Section(header: HStack {
                                Text("Stazioni Recenti")
                                Spacer()
                                Button("Cancella") {
                                    manager.clearRecentStations()
                                    manager.clearViewedRecentStations()
                                    Haptics.play(.medium)
                                }
                                .font(.caption)
                                .foregroundColor(.red)
                            }) {
                                ForEach(recentStations, id: \.id) { station in
                                    Button {
                                        selectStationByName(station.nomeLungo)
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "building.2.crop.circle.fill")
                                                .foregroundColor(.orange)
                                                .font(.body)
                                                .frame(width: 24)
                                            Text(station.nomeLungo.formattedStationName)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Spacer()
                                            if resolvingStationName == station.nomeLungo {
                                                ProgressView()
                                                    .scaleEffect(0.8)
                                            } else if selectedName.lowercased() == station.nomeLungo.lowercased() {
                                                Image(systemName: "checkmark")
                                                    .foregroundColor(.blue)
                                                    .fontWeight(.bold)
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                    .disabled(resolvingStationName != nil)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            manager.removeRecentStation(name: station.nomeLungo, vtID: station.vtID)
                                            Haptics.play(.light)
                                        } label: {
                                            Label("Elimina", systemImage: "trash.fill")
                                        }
                                    }
                                }
                            }
                        }
                        
                        if nearbyStations.isEmpty && recentStations.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 36))
                                    .foregroundColor(.secondary.opacity(0.6))
                                Text("Cerca una stazione")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("Inizia a digitare nella barra in alto per cercare qualsiasi stazione ferroviaria.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Chiudi") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
                    locationManager.requestLocation()
                }
            }
            .task {
                if autoFocusSearch {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    guard !Task.isCancelled else { return }
                    isSearchFocused = true
                }
            }
            .onDisappear {
                searchTask?.cancel()
                searchTask = nil
                manager.isSearching = false
            }
            .onChange(of: query) { oldValue, newValue in
                searchTask?.cancel()
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    manager.searchTrenitaliaLocations = []
                    manager.isSearching = false
                } else {
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        guard !Task.isCancelled else { return }
                        await manager.searchTravelLocations(query: trimmed)
                    }
                }
            }
        }
    }
    
    private func selectStationByName(_ name: String) {
        resolvingStationName = name
        searchTask?.cancel()
        searchTask = Task {
            // Step 1: Query exact name
            await manager.searchTravelLocations(query: name)
            guard !Task.isCancelled else { return }
            
            // Step 2: Query space-cleaned name
            if manager.searchTrenitaliaLocations.isEmpty {
                let spaceCleaned = name
                    .replacingOccurrences(of: "-", with: " ")
                    .replacingOccurrences(of: "/", with: " ")
                    .replacingOccurrences(of: ".", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if spaceCleaned != name && spaceCleaned.count >= 2 {
                    await manager.searchTravelLocations(query: spaceCleaned)
                }
            }
            guard !Task.isCancelled else { return }
            
            // Step 3: Progressive fallback - extract primary keyword before hyphen or slash
            let separatorParts = name.components(separatedBy: CharacterSet(charactersIn: "-/"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count >= 2 }
            
            var usedQuery = name
            if manager.searchTrenitaliaLocations.isEmpty, let primary = separatorParts.first {
                usedQuery = primary
                await manager.searchTravelLocations(query: primary)
            }
            
            // Step 4: If still empty and there was a secondary part, try second part
            if manager.searchTrenitaliaLocations.isEmpty, separatorParts.count > 1 {
                let secondary = separatorParts[1]
                    .replacingOccurrences(of: "S.", with: "San ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if secondary.count >= 2 {
                    usedQuery = secondary
                    await manager.searchTravelLocations(query: secondary)
                }
            }
            
            // Step 5: Find best match
            let normalizedTarget = name.lowercased().replacingOccurrences(of: " ", with: "")
            let match = manager.searchTrenitaliaLocations.first { loc in
                loc.name.lowercased().replacingOccurrences(of: " ", with: "") == normalizedTarget
            } ?? manager.searchTrenitaliaLocations.first { loc in
                if let primary = separatorParts.first?.lowercased() {
                    return loc.name.lowercased().contains(primary)
                }
                return false
            } ?? manager.searchTrenitaliaLocations.first
            
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if let match = match {
                    let resolved = manager.resolveStation(name: match.name)
                    selectedName = resolved.name.formattedStationName
                    selectedID = String(match.id)
                    let vt = resolved.vtID ?? manager.getVtID(for: resolved.name) ?? ""
                    manager.addToRecentStations(VTSearchStation(nomeLungo: resolved.name, nomeBreve: resolved.name, vtID: vt))
                    manager.addToViewedRecentStations(name: resolved.name, vtID: vt)
                    onStationSelected?(resolved)
                    Haptics.play(.medium)
                    dismiss()
                } else {
                    query = usedQuery
                    resolvingStationName = nil
                }
            }
        }
    }
}

struct TravelSolutionRow: View {
    @EnvironmentObject var manager: TrainManager
    let solution: TravelSolution
    
    var isDirect: Bool {
        solution.segments.count <= 1
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Text(solution.departureTime)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    Text(solution.arrivalTime)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    if manager.isTripSaved(solution: solution) {
                        Image(systemName: "bookmark.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(solution.duration)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                .foregroundColor(.secondary)
            }
            
            HStack {
                Text("\(solution.origin) ➔ \(solution.destination)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            
            HStack(spacing: 8) {
                if isDirect {
                    Text("Diretto")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .clipShape(Capsule())
                } else {
                    let changes = max(1, solution.segments.count - 1)
                    Text("\(changes) \(changes == 1 ? "cambio" : "cambi")")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .clipShape(Capsule())
                }
                
                let trainSummary = solution.segments
                    .map { seg -> String in
                        if seg.trainCategory.contains("Metro") {
                            return seg.trainCategory
                        } else if seg.isStationWalk || seg.trainCategory.contains("piedi") {
                            return "A piedi"
                        } else if !seg.trainNumber.isEmpty {
                            return "\(seg.trainCategory) \(seg.trainNumber)"
                        } else {
                            return seg.trainCategory
                        }
                    }
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    .joined(separator: " • ")
                
                Text(trainSummary.isEmpty ? "\(solution.category) \(solution.trainNumber)" : trainSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Spacer()
            }
        }
        .padding(.vertical, 4)
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
            
            Button {
                manager.toggleSavedTrip(solution: solution)
                Haptics.play(.medium)
            } label: {
                Label(
                    manager.isTripSaved(solution: solution) ? "Rimuovi viaggio salvato" : "Salva viaggio",
                    systemImage: manager.isTripSaved(solution: solution) ? "bookmark.fill" : "bookmark"
                )
            }
        }
    }
}

struct TravelSearchView: View {
    var body: some View {
        SearchView(isTravelOnly: true)
    }
}

struct SearchView: View {
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var locationManager: LocationManager
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var aiManager = AIFeatureManager.shared
    
    var isTravelOnly: Bool
    var initialAssistantMode: Bool
    var autoStartVoice: Bool
    var initialQuery: String?
    var initialOriginName: String?
    var initialOriginID: String?
    var initialDestName: String?
    var initialDestID: String?
    var autoSearchSolutions: Bool
    /// 0 = Soluzioni, 1 = Assistente, 2 = Treni e Stazioni
    @State private var currentPage: Int
    @State private var navigationPath = NavigationPath()

    private var isAssistantMode: Bool {
        !isTravelOnly && currentPage == 1
    }
    
    init(
        isTravelOnly: Bool = false,
        initialTab: Int = 1,
        initialScope: SearchScope? = nil,
        initialAssistantMode: Bool = false,
        autoStartVoice: Bool = false,
        initialQuery: String? = nil,
        initialOriginName: String? = nil,
        initialOriginID: String? = nil,
        initialDestName: String? = nil,
        initialDestID: String? = nil,
        autoSearchSolutions: Bool = false
    ) {
        self.isTravelOnly = isTravelOnly
        self.initialAssistantMode = initialAssistantMode
        self.autoStartVoice = autoStartVoice
        self.initialQuery = initialQuery
        self.initialOriginName = initialOriginName
        self.initialOriginID = initialOriginID
        self.initialDestName = initialDestName
        self.initialDestID = initialDestID
        self.autoSearchSolutions = autoSearchSolutions
        let resolvedTab: Int = {
            if isTravelOnly { return 1 }
            if let initialScope {
                return initialScope == .solutions ? 1 : 0
            }
            return initialTab
        }()
        let startsInAssistant = !isTravelOnly && (initialAssistantMode || !(initialQuery ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let initialPage: Int = startsInAssistant ? 1 : (resolvedTab == 1 ? 0 : 2)
        _currentPage = State(initialValue: initialPage)
    }
    
    // TAB 0 State
    @AppStorage("search_origin_name") private var originName = ""
    @AppStorage("search_origin_id") private var originID = ""
    @AppStorage("search_dest_name") private var destName = ""
    @AppStorage("search_dest_id") private var destID = ""
    @State private var searchDate = Date()
    @State private var showOriginSearch = false
    @State private var showDestSearch = false
    @State private var hasSearchedSolutions = false
    
    // Assistant State
    @StateObject private var voiceController = VoiceSearchController()
    @State private var assistantQuery = ""
    @State private var isAssistantRunning = false
    @State private var assistantLoadingStep = "Interpreto la richiesta..."
    @State private var assistantResult: SmartQueryExecutionResult? = nil
    @State private var assistantParsed: SmartTrainQuery? = nil
    @State private var assistantStatusMessage: String? = nil
    @State private var assistantNeedsUpgradeMessage: String? = nil
    @State private var showPaywallSheet = false
    @State private var didHandleAutoVoice = false
    @State private var didHandleInitialQuery = false
    @State private var didHandleInitialRoute = false
    @State private var assistantSearchTask: Task<Void, Never>? = nil
    @State private var activeAssistantSearchID = UUID()
    @FocusState private var isAssistantFieldFocused: Bool
    
    // TAB 1 State
    @State private var query = ""
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var cachedNearbyStations: [Station] = []
    @FocusState private var isTrainsFieldFocused: Bool

    private var allRecentTrains: [SavedTrain] {
        Array(manager.unifiedRecentTrains.prefix(2))
    }

    private var allRecentStations: [VTSearchStation] {
        Array(manager.unifiedRecentStations.prefix(4))
    }

    private var nearbyStations: [Station] {
        cachedNearbyStations
    }

    private func refreshCachedNearbyStations() {
        guard let userLoc = locationManager.userLocation else {
            cachedNearbyStations = []
            return
        }
        let validCandidates = manager.allRFIStations.compactMap { st -> (station: RFIStation, distance: CLLocationDistance)? in
            guard let lat = st.lat, let lon = st.lon else { return nil }
            let loc = CLLocation(latitude: lat, longitude: lon)
            let dist = loc.distance(from: userLoc)
            return (st, dist)
        }
        let sorted = validCandidates.sorted { $0.distance < $1.distance }
        cachedNearbyStations = sorted.prefix(3).map { item in
            let st = item.station
            return Station(name: st.name, rfiID: st.rfiID, vtID: st.vtID, lat: st.lat, lon: st.lon)
        }
    }

    private func switchSearchPage(to newPage: Int) {
        guard currentPage != newPage else { return }
        if isAssistantFieldFocused { isAssistantFieldFocused = false }
        if isTrainsFieldFocused { isTrainsFieldFocused = false }
        if currentPage == 1 {
            voiceController.stopListening(triggerFinal: false)
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            currentPage = newPage
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                if !isTravelOnly {
                    let isSolutionsSelected = currentPage == 0
                    let isTrainsSelected = currentPage == 2

                    HStack(spacing: 10) {
                        searchModePill(
                            title: "Soluzioni",
                            systemImage: "map.fill",
                            isSelected: isSolutionsSelected,
                            minimumScaleFactor: 0.85
                        ) {
                            Haptics.play(.light)
                            switchSearchPage(to: 0)
                        }

                        Button {
                            Haptics.play(.medium)
                            if isAssistantMode {
                                if voiceController.isListening {
                                    voiceController.stopListening(triggerFinal: true)
                                } else {
                                    startVoiceInput()
                                }
                            } else {
                                switchSearchPage(to: 1)
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: voiceController.isListening
                                                ? [.red, .pink, .orange]
                                                : [.indigo, .purple, .cyan],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 38, height: 38)
                                    .shadow(
                                        color: (voiceController.isListening ? Color.pink : Color.purple).opacity(isAssistantMode ? 0.45 : 0.18),
                                        radius: isAssistantMode ? 6 : 3
                                    )

                                Image(systemName: voiceController.isListening ? "waveform" : "sparkles")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                                    .symbolEffect(.variableColor.iterative, isActive: voiceController.isListening)
                            }
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(isAssistantMode ? 0.28 : 0.08), lineWidth: isAssistantMode ? 1.5 : 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isAssistantMode ? "Parla con l'assistente" : "Assistente intelligente")

                        searchModePill(
                            title: "Treni e Stazioni",
                            systemImage: "magnifyingglass",
                            isSelected: isTrainsSelected,
                            minimumScaleFactor: 0.8
                        ) {
                            Haptics.play(.light)
                            switchSearchPage(to: 2)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
                    .background(Color(.systemGroupedBackground))
                }

                if isTravelOnly {
                    travelSolutionsTab
                } else {
                    TabView(selection: $currentPage) {
                        travelSolutionsTab
                            .tag(0)
                        smartAssistantTab
                            .tag(1)
                        trainsAndStationsTab
                            .tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .onChange(of: currentPage) { oldPage, newPage in
                        if oldPage == 1 && newPage != 1 {
                            voiceController.stopListening(triggerFinal: false)
                        }
                        if newPage == 0 {
                            if isAssistantFieldFocused { isAssistantFieldFocused = false }
                            if isTrainsFieldFocused { isTrainsFieldFocused = false }
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Chiudi") {
                        voiceController.stopListening(triggerFinal: false)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                }

                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Text(isTravelOnly ? "Cerca Viaggio" : (isAssistantMode ? "Assistente" : "Cerca"))
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.primary)
                        if !isTravelOnly && isAssistantMode {
                            BetaBadgeView()
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.snappy(duration: 0.22), value: isAssistantMode)
                }
            }
            .onChange(of: locationManager.userLocation) { _, _ in
                refreshCachedNearbyStations()
            }
            .sheet(isPresented: $showOriginSearch) {
                StationSelectionSheet(selectedName: $originName, selectedID: $originID, title: "Stazione di Partenza")
            }
            .sheet(isPresented: $showDestSearch) {
                StationSelectionSheet(selectedName: $destName, selectedID: $destID, title: "Stazione di Arrivo")
            }
            .sheet(isPresented: $showPaywallSheet) {
                SupportPaywallSheet()
                    .environmentObject(manager)
            }
            .onChange(of: voiceController.transcript) { _, newText in
                if voiceController.isListening && !newText.isEmpty {
                    assistantQuery = newText
                }
            }
            .onAppear {
                refreshCachedNearbyStations()
                if let initOrig = initialOriginName?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let initDest = initialDestName?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !initOrig.isEmpty, !initDest.isEmpty,
                   !didHandleInitialRoute {
                    didHandleInitialRoute = true
                    currentPage = 0
                    let resolvedOrig = manager.resolveStation(name: initOrig, fallbackVtID: initialOriginID, fallbackRfiID: initialOriginID)
                    let resolvedDest = manager.resolveStation(name: initDest, fallbackVtID: initialDestID, fallbackRfiID: initialDestID)
                    originName = resolvedOrig.name
                    originID = (initialOriginID?.isEmpty == false ? initialOriginID : nil) ?? resolvedOrig.rfiID ?? resolvedOrig.vtID ?? initOrig
                    destName = resolvedDest.name
                    destID = (initialDestID?.isEmpty == false ? initialDestID : nil) ?? resolvedDest.rfiID ?? resolvedDest.vtID ?? initDest
                    searchDate = Date()
                    if autoSearchSolutions {
                        performSolutionsSearch(
                            originName: originName,
                            originID: originID,
                            destName: destName,
                            destID: destID,
                            date: searchDate
                        )
                    }
                } else if manager.travelSolutionsSource == .searchView,
                          !manager.travelSolutions.isEmpty,
                          !originID.isEmpty,
                          !destID.isEmpty,
                          originID == manager.lastSearchSolutionsOriginID,
                          destID == manager.lastSearchSolutionsDestID {
                    if let savedDate = manager.lastSearchSolutionsDate {
                        searchDate = savedDate
                    }
                    hasSearchedSolutions = true
                } else {
                    hasSearchedSolutions = false
                    if originID.isEmpty || destID.isEmpty || manager.travelSolutionsSource == .searchView {
                        manager.clearSearchSolutions()
                    }
                }
                if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
                    locationManager.requestLocation()
                }
                if let initQ = initialQuery?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !initQ.isEmpty,
                   !didHandleInitialQuery {
                    didHandleInitialQuery = true
                    currentPage = 1
                    assistantQuery = initQ
                    runAssistantSearch(inputMode: "text")
                } else if autoStartVoice && isAssistantMode && !didHandleAutoVoice {
                    didHandleAutoVoice = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        startVoiceInput()
                    }
                }
            }
        }
        .onDisappear {
            voiceController.stopListening(triggerFinal: false)
            assistantSearchTask?.cancel()
            navigationPath = NavigationPath()
        }
    }

    @ViewBuilder
    private func searchModePill(
        title: LocalizedStringKey,
        systemImage: String,
        isSelected: Bool,
        minimumScaleFactor: CGFloat = 0.85,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(minimumScaleFactor)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .padding(.horizontal, 8)
            .foregroundColor(isSelected ? .white : .primary)
            .background(
                Capsule()
                    .fill(isSelected ? Color.blue : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(isSelected ? 0 : 0.08), lineWidth: 0.5)
            )
            .shadow(color: isSelected ? Color.blue.opacity(0.22) : .clear, radius: 4, y: 1)
        }
        .buttonStyle(.plain)
    }

    private var hasSearchGeneratedResults: Bool {
        !manager.isSearchingSolutions
        && manager.travelSolutionsSource == .searchView
        && !manager.travelSolutions.isEmpty
        && !originID.isEmpty
        && !destID.isEmpty
    }

    private var inputsMatchLastSearch: Bool {
        guard !originID.isEmpty,
              !destID.isEmpty,
              originID == manager.lastSearchSolutionsOriginID,
              destID == manager.lastSearchSolutionsDestID,
              let lastDate = manager.lastSearchSolutionsDate else {
            return false
        }
        return Calendar.current.isDate(searchDate, equalTo: lastDate, toGranularity: .minute)
    }

    private var shouldShowClearSolutionsButton: Bool {
        hasSearchGeneratedResults && inputsMatchLastSearch
    }

    private func performSolutionsSearch(
        originName origName: String,
        originID origID: String,
        destName dName: String,
        destID dID: String,
        date: Date
    ) {
        hasSearchedSolutions = true
        manager.addRecentRoute(originName: origName, originID: origID, destName: dName, destID: dID)
        Task {
            await manager.searchTravelSolutions(
                originID: origID,
                destID: dID,
                date: date,
                originName: origName,
                destName: dName,
                source: .searchView,
                onResolvedIDs: { newOrig, newDest in
                    originID = newOrig
                    destID = newDest
                    manager.addRecentRoute(originName: origName, originID: newOrig, destName: dName, destID: newDest)
                }
            )
        }
    }

    private func clearSolutionsSearch() {
        Haptics.play(.light)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            originName = ""
            originID = ""
            destName = ""
            destID = ""
            searchDate = Date()
            hasSearchedSolutions = false
            manager.clearSearchSolutions()
        }
    }

    // MARK: - Smart Assistant Tab

    private struct VoiceWaveView: View {
        let audioLevel: CGFloat
        @State private var phase: Double = 0

        var body: some View {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                HStack(spacing: 4) {
                    ForEach(0..<16, id: \.self) { idx in
                        let norm = Double(idx) / 15.0
                        let envelope = sin(norm * .pi)
                        let wave = abs(sin(t * 7.5 + Double(idx) * 0.55))
                        let levelBoost = max(0.18, Double(audioLevel))
                        let height = max(8, min(42, 10 + CGFloat(wave * envelope * levelBoost * 34)))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.indigo, .purple, .pink],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: 4, height: height)
                    }
                }
                .frame(height: 44)
            }
        }
    }

    private var assistantEngineLabel: String {
        switch SmartQueryEnginePolicy.resolve(
            hasSupport: manager.hasSupport(),
            hasAppleIntelligence: aiManager.isAppleIntelligenceAvailable,
            aiModeChoice: aiManager.aiModeChoice
        ) {
        case .geminiCloud: return "Cloud"
        case .appleIntelligence: return "Apple Intelligence"
        case .localExactOnly: return "Locale"
        }
    }

    private let assistantExamples: [String] = [
        "Voglio andare da Milano Cadorna a Novara alle 16:00 di domani",
        "Treno delle 11:34 da Magenta",
        "Primo treno da Rho Fiera a Torino",
        "Partenze Milano Rogoredo",
        "Portami a Milano Repubblica"
    ]

    private var smartAssistantTab: some View {
        VStack(spacing: 0) {
            // Barra di ricerca capsula in alto coerente con "Treni e Stazioni"
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                    .font(.system(size: 16, weight: .medium))

                TextField("", text: $assistantQuery)
                    .font(.system(size: 17))
                    .submitLabel(.search)
                    .textInputAutocapitalization(.sentences)
                    .focused($isAssistantFieldFocused)
                    .onSubmit {
                        voiceController.stopListening(triggerFinal: false)
                        runAssistantSearch()
                    }

                if !voiceController.isListening {
                    if !assistantQuery.isEmpty {
                        Button {
                            clearAssistantState()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 18))
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cancella ricerca")
                    }

                    Button {
                        Haptics.play(.medium)
                        startVoiceInput()
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.purple)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Detta richiesta")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemFill))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(voiceController.isListening ? Color.purple.opacity(0.65) : Color.clear, lineWidth: 1.5)
            )
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 4)
            .background(Color(.systemGroupedBackground))

            if !manager.hasSupport() {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        Haptics.play(.light)
                        showPaywallSheet = true
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.caption.bold())
                                    .foregroundColor(.purple)
                                Text("Elaborazione locale (\(assistantEngineLabel))")
                                    .font(.caption.bold())
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("Passa a Pro")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(
                                        LinearGradient(
                                            colors: [.indigo, .purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                            }
                            Text("Chiedi orari, partenze, ritardi o tratte scrivendo o parlando. Senza Pro usa l'elaborazione locale sul dispositivo e può non essere precisa.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.purple.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.purple.opacity(0.22), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 6)
                .background(Color(.systemGroupedBackground))
            } else {
                let engine = SmartQueryEnginePolicy.resolve(
                    hasSupport: true,
                    hasAppleIntelligence: aiManager.isAppleIntelligenceAvailable,
                    aiModeChoice: aiManager.aiModeChoice
                )
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: engine == .geminiCloud ? "cloud.fill" : "cpu")
                        .font(.caption2)
                        .foregroundColor(.purple)
                        .padding(.top, 2)
                    Text(
                        engine == .geminiCloud
                        ? "Chiedi orari, partenze, ritardi o soluzioni in linguaggio naturale. Con In Orario Pro usa il Cloud per risposte più rapide e precise."
                        : "Chiedi orari, partenze, ritardi o soluzioni in linguaggio naturale. Stai usando l'elaborazione locale (\(assistantEngineLabel)): puoi passare al Cloud dalle Impostazioni."
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .padding(.bottom, 6)
                .background(Color(.systemGroupedBackground))
            }

            if voiceController.isListening {
                VStack(spacing: 12) {
                    VoiceWaveView(audioLevel: voiceController.audioLevel)
                    Text("Ti ascolto, tocca Cerca quando hai finito")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 12) {
                        Button {
                            Haptics.play(.light)
                            voiceController.stopListening(triggerFinal: false)
                        } label: {
                            Label("Annulla", systemImage: "xmark")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Color(.tertiarySystemFill))
                                .foregroundColor(.primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            Haptics.play(.medium)
                            voiceController.stopListening(triggerFinal: true)
                        } label: {
                            Label("Cerca", systemImage: "magnifyingglass")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    LinearGradient(
                                        colors: [.indigo, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color(.systemGroupedBackground))
                .transition(.opacity)
            }

            if let voiceErr = voiceController.errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text(voiceErr)
                        .font(.caption)
                        .foregroundColor(.orange)
                    if voiceController.permissionDenied,
                       let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        Button("Apri Impostazioni") {
                            UIApplication.shared.open(settingsURL)
                        }
                        .font(.caption.bold())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
                .background(Color(.systemGroupedBackground))
            }

            List {
                if isAssistantRunning {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(assistantLoadingStep)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }

                if let upgradeMsg = assistantNeedsUpgradeMessage {
                    Section(header: Text("Richiesta Complessa")) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Serve comprensione avanzata", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundColor(.purple)
                            Text(upgradeMsg)
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            HStack(spacing: 10) {
                                Button {
                                    showPaywallSheet = true
                                } label: {
                                    Label("Sblocca In Orario Pro", systemImage: "crown.fill")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.purple)
                                        .foregroundColor(.white)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    switchSearchPage(to: 0)
                                } label: {
                                    Text("Usa scheda Soluzioni")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color(.tertiarySystemFill))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                } else if let statusMsg = assistantStatusMessage {
                    Section {
                        Label(statusMsg, systemImage: "info.circle")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    }
                }

                if let parsed = assistantParsed {
                    Section(header: Text("Richiesta Interpretata")) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(parsed.displaySummary(fallbackQuery: assistantQuery))
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            HStack(spacing: 8) {
                                if let d = parsed.targetDate {
                                    Text("Data: \(d)")
                                }
                                if let t = parsed.targetTime {
                                    Text("Ora: \(t)")
                                }
                                if let eng = parsed.engineUsed {
                                    Text("• \(engineDisplayName(eng))")
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                if let result = assistantResult {
                    assistantResultSections(result)
                }

                if !isAssistantRunning && assistantResult == nil && assistantNeedsUpgradeMessage == nil {
                    if !manager.recentAssistantQueries.isEmpty {
                        Section(header: HStack {
                            Text("Ricerche recenti")
                            Spacer()
                            Button("Cancella") {
                                manager.clearRecentAssistantQueries()
                                Haptics.play(.medium)
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                        }) {
                            ForEach(Array(manager.recentAssistantQueries.prefix(4)), id: \.self) { recentQ in
                                Button {
                                    Haptics.play(.light)
                                    assistantQuery = recentQ
                                    runAssistantSearch()
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .foregroundColor(.secondary)
                                        Text(recentQ)
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                            .multilineTextAlignment(.leading)
                                        Spacer()
                                        Image(systemName: "arrow.up.left")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        manager.removeRecentAssistantQuery(recentQ)
                                        Haptics.play(.light)
                                    } label: {
                                        Label("Elimina", systemImage: "trash.fill")
                                    }
                                }
                            }
                        }
                    }

                    Section(header: Text("Esempi di richieste")) {
                        ForEach(assistantExamples, id: \.self) { sample in
                            Button {
                                Haptics.play(.light)
                                assistantQuery = sample
                                runAssistantSearch()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "text.bubble.fill")
                                        .foregroundColor(.purple)
                                    Text(sample)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: "arrow.up.left")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    @ViewBuilder
    private func assistantResultSections(_ result: SmartQueryExecutionResult) -> some View {
        switch result {
        case .trainAtTime(let train, let station, let sample, let requestedTime):
            Section(header: Text("Partenza da \(station.name.formattedStationName) (\(requestedTime))")) {
                if let matched = train {
                    NavigationLink(destination: TrainStopsView(train: matched, showCloseButton: false)) {
                        assistantTrainRow(matched, highlightBadge: "TROVATO")
                    }
                } else {
                    Text("Nessun treno trovato in partenza da \(station.name.formattedStationName) intorno alle \(requestedTime).")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                NavigationLink(destination: SmartBoardView(station: station)) {
                    Label("Apri tabellone completo \(station.name.formattedStationName)", systemImage: "list.bullet.rectangle.portrait")
                        .font(.subheadline.bold())
                        .foregroundColor(.blue)
                }
            }

            if !sample.isEmpty {
                let others = sample.filter { $0.id != train?.id }.prefix(5)
                if !others.isEmpty {
                    Section(header: Text("Altri treni vicini in partenza")) {
                        ForEach(Array(others)) { tr in
                            NavigationLink(destination: TrainStopsView(train: tr, showCloseButton: false)) {
                                assistantTrainRow(tr, highlightBadge: nil)
                            }
                        }
                    }
                }
            }

        case .trainStatus(let train):
            Section(header: Text("Stato Treno Reale")) {
                NavigationLink(destination: TrainStopsView(train: train, showCloseButton: false)) {
                    assistantTrainRow(train, highlightBadge: nil)
                }
            }

        case .stationBoard(let station, let isArrivals):
            Section(header: Text(isArrivals ? "Arrivi Stazione" : "Partenze Stazione")) {
                NavigationLink(destination: SmartBoardView(station: station)) {
                    HStack(spacing: 12) {
                        Image(systemName: "building.2.crop.circle.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(station.name.formattedStationName)
                                .font(.headline)
                            Text("Apri tabellone live (\(isArrivals ? "Arrivi" : "Partenze"))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

        case .solutions(let solutions, let origin, let destination, let resolvedOrigID, let resolvedDestID, let searchDt):
            Section(header: Text("\(origin.formattedStationName) → \(destination.formattedStationName) • \(assistantFormattedDate(searchDt))")) {
                if solutions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nessuna soluzione reale trovata per questa richiesta.")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Prova a cambiare orario o verifica i nomi delle stazioni nella scheda Soluzioni.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Apri nella scheda Soluzioni") {
                            applyToSolutionsTab(
                                origin: origin,
                                originID: resolvedOrigID,
                                destination: destination,
                                destID: resolvedDestID,
                                date: searchDt,
                                solutions: []
                            )
                        }
                        .font(.subheadline.bold())
                    }
                    .padding(.vertical, 6)
                } else {
                    Button {
                        applyToSolutionsTab(
                            origin: origin,
                            originID: resolvedOrigID,
                            destination: destination,
                            destID: resolvedDestID,
                            date: searchDt,
                            solutions: solutions
                        )
                    } label: {
                        Label("Apri queste \(solutions.count) soluzioni nella scheda Soluzioni", systemImage: "arrow.right.doc.on.clipboard")
                            .font(.subheadline.bold())
                            .foregroundColor(.blue)
                    }

                    ForEach(Array(solutions.enumerated()), id: \.element.id) { index, solution in
                        NavigationLink(destination: TravelSolutionDetailsView(solution: solution)) {
                            VStack(alignment: .leading, spacing: 6) {
                                if index == 0 {
                                    let isFirstRequested = assistantQuery.lowercased().contains("primo") || assistantQuery.lowercased().contains("prossimo")
                                    Text(isFirstRequested ? "PRIMO TRENO UTILE" : "SOLUZIONE MIGLIORE")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.green.opacity(0.15))
                                        .foregroundColor(.green)
                                        .clipShape(Capsule())
                                }
                                TravelSolutionRow(solution: solution)
                            }
                        }
                    }
                }
            }

        case .message(let text):
            Section {
                Label(text, systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func assistantTrainRow(_ train: Train, highlightBadge: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let badge = highlightBadge {
                Text(badge)
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.14))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
            }
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(train.category.isEmpty ? "Treno" : train.category) \(train.number)")
                        .font(.headline)
                    Text("Dir. \(train.destination.formattedStationName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(train.time)
                        .font(.title3.bold().monospacedDigit())
                    HStack(spacing: 6) {
                        if !train.delay.isEmpty {
                            Text(train.delay)
                                .font(.caption.bold())
                                .foregroundColor(train.delay.contains("+") || train.delay.contains("Soppresso") ? .red : .green)
                        }
                        if !train.platform.isEmpty && train.platform != "--" {
                            Text("Bin. \(train.platform)")
                                .font(.caption2.bold())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color(.tertiarySystemFill))
                                .cornerRadius(4)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func engineDisplayName(_ engine: String) -> String {
        switch engine {
        case "gemini_cloud": return "Cloud"
        case "apple_intelligence": return "Apple Intelligence"
        case "local_exact": return "Locale"
        default: return engine
        }
    }

    private func clearAssistantState() {
        assistantSearchTask?.cancel()
        assistantQuery = ""
        assistantResult = nil
        assistantParsed = nil
        assistantStatusMessage = nil
        assistantNeedsUpgradeMessage = nil
        isAssistantRunning = false
    }

    private func assistantFormattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        f.dateFormat = "d MMM HH:mm"
        return f.string(from: date)
    }

    private func applyToSolutionsTab(
        origin: String,
        originID resolvedOriginID: String,
        destination: String,
        destID resolvedDestID: String,
        date: Date,
        solutions: [TravelSolution]
    ) {
        self.originName = origin
        self.originID = resolvedOriginID
        self.destName = destination
        self.destID = resolvedDestID
        self.searchDate = date
        manager.travelSolutions = solutions
        manager.travelSolutionsSource = .searchView
        manager.lastSearchSolutionsOriginID = resolvedOriginID
        manager.lastSearchSolutionsDestID = resolvedDestID
        manager.lastSearchSolutionsDate = date
        manager.addRecentRoute(originName: origin, originID: resolvedOriginID, destName: destination, destID: resolvedDestID)
        self.hasSearchedSolutions = true
        self.switchSearchPage(to: 0)
    }

    private func contextualVoiceStrings() -> [String] {
        var ctx: [String] = [
            "In Orario", "Milano Cadorna", "Milano Nord Cadorna",
            "Milano Centrale", "Milano Porta Garibaldi", "Milano Rogoredo",
            "Milano Repubblica", "Milano Dateo", "Magenta", "Novara",
            "Domodossola", "Rho Fiera", "Torino", "Torino Porta Nuova", "Roma Termini",
            "partenze", "arrivi", "primo treno", "domani", "oggi pomeriggio",
            "portami a casa", "portami al lavoro", "treno delle"
        ]
        if let nearby = locationManager.manualNearbyStation?.name ?? locationManager.nearbyStation?.name {
            ctx.append(nearby)
        }
        ctx.append(contentsOf: SupporterCommuteManager.shared.origins.prefix(8))
        ctx.append(contentsOf: SupporterCommuteManager.shared.destinations.prefix(8))
        for rt in manager.smartRoutes.prefix(8) {
            ctx.append(rt.originName)
            ctx.append(rt.destinationName)
        }
        for favRt in manager.favoriteRoutes.prefix(8) {
            ctx.append(favRt.originName)
            ctx.append(favRt.destinationName)
        }
        ctx.append(contentsOf: manager.myStations.prefix(10).map { $0.name })
        ctx.append(contentsOf: manager.recentStations.prefix(10).map { $0.nomeLungo })
        ctx.append(contentsOf: manager.favoriteTrains.prefix(10).map { $0.number })
        return ctx
    }

    private func startVoiceInput() {
        isAssistantFieldFocused = false
        assistantStatusMessage = nil
        assistantNeedsUpgradeMessage = nil
        voiceController.startListening(contextualStrings: contextualVoiceStrings()) { spoken in
            assistantQuery = spoken
            runAssistantSearch(inputMode: "voice")
        }
    }

    private func runAssistantSearch(inputMode: String = "text") {
        let q = assistantQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        assistantSearchTask?.cancel()
        let currentSearchID = UUID()
        activeAssistantSearchID = currentSearchID
        isAssistantRunning = true
        assistantLoadingStep = "Interpreto la richiesta..."
        assistantResult = nil
        assistantParsed = nil
        assistantStatusMessage = nil
        assistantNeedsUpgradeMessage = nil

        let initialNearby = locationManager.manualNearbyStation ?? locationManager.nearbyStation
        let favStationNames = manager.myStations.map { $0.name }
        let favTrainNumbers = manager.favoriteTrains.map { $0.number }
        let homeStList = SupporterCommuteManager.shared.origins
        let workStList = SupporterCommuteManager.shared.destinations
        let knownStations = manager.allRFIStations.isEmpty ? SmartQueryExecutor.bundledRFIStations() : manager.allRFIStations
        let hasSup = manager.hasSupport()
        let selectedChoice = aiManager.aiModeChoice
        let lowerQ = q.lowercased()
        let needsFreshLocation = initialNearby == nil &&
            (lowerQ.contains("portami") || lowerQ.contains("da qui") || lowerQ.contains("qui vicino") || lowerQ.contains("stazione più vicina")) &&
            !lowerQ.contains(" da ") &&
            (locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways)

        assistantSearchTask = Task {
            let watchdog = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 22_000_000_000)
                guard !Task.isCancelled,
                      self.activeAssistantSearchID == currentSearchID,
                      self.isAssistantRunning else { return }
                self.assistantSearchTask?.cancel()
                self.isAssistantRunning = false
                if self.assistantResult == nil && self.assistantStatusMessage == nil && self.assistantNeedsUpgradeMessage == nil {
                    let timeoutMsg = "La ricerca ha impiegato troppo tempo. Riprova tra un attimo."
                    self.assistantStatusMessage = timeoutMsg
                    SmartQueryParser.shared.logAnonymousQuery(
                        rawQuery: q,
                        inputMode: inputMode,
                        engine: "none",
                        outcome: "timeout",
                        parsed: self.assistantParsed,
                        resultSummary: timeoutMsg
                    )
                }
            }
            defer {
                watchdog.cancel()
                if self.activeAssistantSearchID == currentSearchID {
                    self.isAssistantRunning = false
                }
            }

            var nearbySt = initialNearby
            if needsFreshLocation {
                self.assistantLoadingStep = "Rilevo la stazione GPS vicina..."
                _ = await locationManager.getCurrentLocation(maxAge: 120, timeout: 2.5)
                guard !Task.isCancelled, self.activeAssistantSearchID == currentSearchID else { return }
                nearbySt = locationManager.manualNearbyStation ?? locationManager.nearbyStation
                self.assistantLoadingStep = "Interpreto la richiesta..."
            }

            let report = await SmartQueryParser.shared.parseDetailed(
                query: q,
                hasSupport: hasSup,
                aiModeChoice: selectedChoice,
                inputMode: inputMode,
                nearbyStation: nearbySt?.name,
                homeStations: homeStList,
                workStations: workStList,
                favoriteStations: favStationNames,
                favoriteTrains: favTrainNumbers,
                knownStations: knownStations
            )
            guard !Task.isCancelled, self.activeAssistantSearchID == currentSearchID else { return }

            switch report.outcome {
            case .parsed(let parsed):
                self.assistantParsed = parsed
                self.assistantLoadingStep = "Cerco i treni reali..."
                let execResult = await SmartQueryExecutor.shared.execute(
                    parsed: parsed,
                    manager: manager,
                    nearbyStation: nearbySt
                )
                guard !Task.isCancelled, self.activeAssistantSearchID == currentSearchID else {
                    SmartQueryParser.shared.logAnonymousQuery(
                        rawQuery: q,
                        inputMode: inputMode,
                        engine: report.engineUsed,
                        outcome: "cancelled",
                        parsed: parsed,
                        resultSummary: "Ricerca annullata dall'utente"
                    )
                    return
                }
                self.assistantResult = execResult
                if execResult.isSuccessfulForHistory {
                    manager.addRecentAssistantQuery(q)
                }
                SmartQueryParser.shared.logAnonymousQuery(
                    rawQuery: q,
                    inputMode: inputMode,
                    engine: report.engineUsed,
                    outcome: execResult.isSuccessfulForHistory ? "ok" : "empty_result",
                    parsed: parsed,
                    resultSummary: execResult.telemetrySummary
                )

            case .needsUpgrade(let msg):
                self.assistantNeedsUpgradeMessage = msg
                SmartQueryParser.shared.logAnonymousQuery(
                    rawQuery: q,
                    inputMode: inputMode,
                    engine: report.engineUsed,
                    outcome: "needs_upgrade",
                    parsed: report.parsedSnapshot,
                    resultSummary: msg
                )

            case .clarification(let msg):
                self.assistantStatusMessage = msg
                SmartQueryParser.shared.logAnonymousQuery(
                    rawQuery: q,
                    inputMode: inputMode,
                    engine: report.engineUsed,
                    outcome: "clarification",
                    parsed: report.parsedSnapshot,
                    resultSummary: msg
                )

            case .error(let msg):
                self.assistantStatusMessage = msg
                SmartQueryParser.shared.logAnonymousQuery(
                    rawQuery: q,
                    inputMode: inputMode,
                    engine: report.engineUsed,
                    outcome: "error",
                    parsed: report.parsedSnapshot,
                    resultSummary: msg
                )
            }
        }
    }
    
    private var travelSolutionsTab: some View {
        List {
            // Unified Route Planning Card (Native InsetGrouped Card)
            Section {
                VStack(spacing: 0) {
                    HStack(alignment: .center, spacing: 14) {
                        // Timeline dots
                        VStack(spacing: 3) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 10, height: 10)
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 2, height: 42)
                            Circle()
                                .fill(Color.red)
                                .frame(width: 10, height: 10)
                        }
                        .padding(.leading, 4)
                        
                        // Stations inputs
                        VStack(spacing: 0) {
                            Button {
                                showOriginSearch = true
                            } label: {
                                HStack {
                                    if originName.isEmpty {
                                        Text("Partenza")
                                            .font(.system(size: 17))
                                            .foregroundColor(.secondary)
                                    } else {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("PARTENZA")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(.secondary)
                                            Text(originName)
                                                .font(.system(size: 17, weight: .semibold))
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.85)
                                        }
                                    }
                                    Spacer()
                                }
                                .frame(height: 46)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            Divider()
                            
                            Button {
                                showDestSearch = true
                            } label: {
                                HStack {
                                    if destName.isEmpty {
                                        Text("Arrivo")
                                            .font(.system(size: 17))
                                            .foregroundColor(.secondary)
                                    } else {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("ARRIVO")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(.secondary)
                                            Text(destName)
                                                .font(.system(size: 17, weight: .semibold))
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.85)
                                        }
                                    }
                                    Spacer()
                                }
                                .frame(height: 46)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // Azioni Tratta (Inverti e Salva Preferito) a destra
                        let hasRoute = !originID.isEmpty && !destID.isEmpty
                        let isFav = hasRoute && manager.isFavoriteRoute(originID: originID, destID: destID)
                        
                        VStack(spacing: 8) {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                    let tmpName = originName
                                    let tmpID = originID
                                    originName = destName
                                    originID = destID
                                    destName = tmpName
                                    destID = tmpID
                                }
                                Haptics.play(.medium)
                                if !originID.isEmpty && !destID.isEmpty {
                                    performSolutionsSearch(
                                        originName: originName,
                                        originID: originID,
                                        destName: destName,
                                        destID: destID,
                                        date: searchDate
                                    )
                                } else {
                                    hasSearchedSolutions = false
                                    manager.clearSearchSolutions()
                                }
                            } label: {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.blue)
                                    .frame(width: 38, height: 38)
                                    .background(Color.blue.opacity(0.12))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            
                            Button {
                                guard hasRoute else { return }
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    manager.toggleFavoriteRoute(originName: originName, originID: originID, destName: destName, destID: destID)
                                }
                                Haptics.play(.medium)
                            } label: {
                                Image(systemName: isFav ? "star.fill" : "star")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(isFav ? .yellow : (hasRoute ? .secondary : .secondary.opacity(0.3)))
                                    .frame(width: 38, height: 38)
                                    .background(isFav ? Color.yellow.opacity(0.18) : (hasRoute ? Color.secondary.opacity(0.12) : Color.secondary.opacity(0.06)))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!hasRoute)
                        }
                        .padding(.trailing, 2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    
                    Divider()
                    
                    // Riga inferiore: Data e Ora a sinistra + Pulsante Ricerca a destra (perfettamente reattivo su ogni schermo)
                    let hasRouteBottom = !originID.isEmpty && !destID.isEmpty
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            DatePicker("", selection: $searchDate, displayedComponents: .date)
                                .labelsHidden()
                                .environment(\.locale, SharedFormatters.italian24HourLocale)
                                .environment(\.timeZone, TimeZone(identifier: "Europe/Rome") ?? .current)
                            Italian24HourTimePicker(selection: $searchDate)
                        }
                        .transaction { $0.animation = nil }
                        
                        Spacer(minLength: 8)
                        
                        Button {
                            if shouldShowClearSolutionsButton {
                                clearSolutionsSearch()
                            } else {
                                Haptics.play(.medium)
                                performSolutionsSearch(
                                    originName: originName,
                                    originID: originID,
                                    destName: destName,
                                    destID: destID,
                                    date: searchDate
                                )
                            }
                        } label: {
                            ZStack {
                                if manager.isSearchingSolutions {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 42, height: 42)
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.9)
                                } else if shouldShowClearSolutionsButton {
                                    Circle()
                                        .fill(Color(.tertiarySystemFill))
                                        .frame(width: 42, height: 42)
                                    Image(systemName: "xmark")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.primary)
                                } else {
                                    Circle()
                                        .fill(hasRouteBottom ? Color.blue : Color.blue.opacity(0.12))
                                        .frame(width: 42, height: 42)
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(hasRouteBottom ? .white : .blue.opacity(0.4))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(manager.isSearchingSolutions || (!shouldShowClearSolutionsButton && !hasRouteBottom))
                        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: shouldShowClearSolutionsButton)
                        .accessibilityLabel(shouldShowClearSolutionsButton ? "Chiudi risultati" : "Cerca Soluzioni")
                        .padding(.trailing, 2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .listRowInsets(EdgeInsets())
            }
            
            // Solutions List
            if manager.isSearchingSolutions {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Ricerca soluzioni su ViaggiaTreno in corso...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 16)
                }
            } else if hasSearchGeneratedResults {
                Section(header: Text("Soluzioni Disponibili (\(manager.travelSolutions.count))")) {
                    ForEach(manager.travelSolutions) { solution in
                        NavigationLink(destination: TravelSolutionDetailsView(solution: solution)) {
                            TravelSolutionRow(solution: solution)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            let isSaved = manager.isTripSaved(solution: solution)
                            Button {
                                withAnimation {
                                    manager.toggleSavedTrip(solution: solution)
                                }
                                Haptics.play(.medium)
                            } label: {
                                Label(
                                    isSaved ? "Rimuovi dai preferiti" : "Salva",
                                    systemImage: isSaved ? "star.slash.fill" : "star.fill"
                                )
                            }
                            .tint(isSaved ? .red : .yellow)
                        }
                    }
                }
            } else if hasSearchedSolutions && manager.travelSolutionsSource == .searchView && !originID.isEmpty && !destID.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "slash.circle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("Nessuna soluzione trovata.")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Prova a cambiare orario di partenza.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            } else {
                if !manager.recentRoutes.isEmpty {
                    Section(header: HStack {
                        Text("Tratte Recenti")
                        Spacer()
                        Button("Cancella") {
                            manager.clearRecentRoutes()
                            Haptics.play(.medium)
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                    }) {
                        ForEach(manager.recentRoutes.prefix(4)) { route in
                            Button {
                                Haptics.play(.light)
                                originName = route.originName
                                originID = route.originID
                                destName = route.destinationName
                                destID = route.destinationID
                                performSolutionsSearch(
                                    originName: route.originName,
                                    originID: route.originID,
                                    destName: route.destinationName,
                                    destID: route.destinationID,
                                    date: searchDate
                                )
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundColor(.blue)
                                    HStack(spacing: 6) {
                                        Text(route.originName.formattedStationName)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Image(systemName: "arrow.right")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text(route.destinationName.formattedStationName)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    manager.removeRecentRoute(route)
                                    Haptics.play(.light)
                                } label: {
                                    Label("Elimina", systemImage: "trash.fill")
                                }
                            }
                        }
                    }
                }

                if !manager.recentViewedTrips.isEmpty {
                    Section(header: HStack {
                        Text("Viaggi Recenti")
                        Spacer()
                        Button("Cancella") {
                            manager.clearRecentViewedTrips()
                            Haptics.play(.medium)
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                    }) {
                        ForEach(manager.recentViewedTrips.prefix(4)) { trip in
                            NavigationLink(destination: TravelSolutionDetailsView(solution: trip.asTravelSolution)) {
                                RecentViewedTripRow(trip: trip)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    manager.removeRecentViewedTrip(id: trip.id)
                                    Haptics.play(.light)
                                } label: {
                                    Label("Elimina", systemImage: "trash.fill")
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private var trainsAndStationsTab: some View {
        VStack(spacing: 0) {
            // Barra di ricerca nativa iOS stile capsula
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16, weight: .medium))
                
                TextField("Cerca treno (es. 9604) o stazione", text: $query)
                    .font(.system(size: 16))
                    .focused($isTrainsFieldFocused)
                    .submitLabel(.search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemFill))
            .clipShape(Capsule())
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .background(Color(.systemGroupedBackground))
            
            List {
                if manager.isSearching {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 16)
                    .listRowBackground(Color.clear)
                } else if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    // 1. Stazioni Vicine (pillole orizzontali, massimo 3)
                    if !nearbyStations.isEmpty {
                        Section(header: Text("Stazioni Vicine")) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(nearbyStations.prefix(3), id: \.id) { st in
                                        NavigationLink(destination: SmartBoardView(station: st).onAppear {
                                            let vtSearch = VTSearchStation(nomeLungo: st.name, nomeBreve: st.name, vtID: st.vtID ?? "")
                                            manager.addToRecentStations(vtSearch)
                                            manager.addToViewedRecentStations(name: st.name, vtID: st.vtID ?? "")
                                        }) {
                                            HStack(spacing: 6) {
                                                Image(systemName: "location.fill")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(.blue)
                                                
                                                Text(st.name.formattedStationName)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundColor(.primary)
                                                
                                                if let lat = st.lat, let lon = st.lon, let userLoc = locationManager.userLocation {
                                                    let d = userLoc.distance(from: CLLocation(latitude: lat, longitude: lon))
                                                    let distStr = d < 1000 ? "\(Int(d))m" : String(format: "%.1fkm", d / 1000.0)
                                                    Text(distStr)
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(Color(.secondarySystemGroupedBackground))
                                            .clipShape(Capsule())
                                            .overlay(
                                                Capsule()
                                                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                                            )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                            }
                            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    
                    // 2. Stazioni Recenti (massimo 4 in verticale)
                    if !allRecentStations.isEmpty {
                        Section(header: HStack {
                            Text("Stazioni Recenti")
                            Spacer()
                            Button("Cancella") {
                                manager.clearRecentStations()
                                manager.clearViewedRecentStations()
                                Haptics.play(.medium)
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                        }) {
                            ForEach(allRecentStations.prefix(4)) { result in
                                let tempStation = manager.resolveStation(name: result.nomeLungo, fallbackVtID: result.vtID)
                                NavigationLink(destination: SmartBoardView(station: tempStation).onAppear {
                                    manager.addToRecentStations(result)
                                    manager.addToViewedRecentStations(name: tempStation.name, vtID: tempStation.vtID ?? result.vtID)
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "building.2.crop.circle.fill")
                                            .foregroundColor(.orange)
                                            .font(.body)
                                            .frame(width: 24)
                                        
                                        Text(tempStation.name.formattedStationName)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                    }
                                    .padding(.vertical, 2)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        manager.removeRecentStation(name: result.nomeLungo, vtID: result.vtID)
                                        Haptics.play(.light)
                                    } label: {
                                        Label("Elimina", systemImage: "trash.fill")
                                    }
                                }
                            }
                        }
                    }
                    
                    // 3. Treni Recenti (uno o due massimo in verticale)
                    if !allRecentTrains.isEmpty {
                        Section(header: HStack {
                            Text("Treni Recenti")
                            Spacer()
                            Button("Cancella") {
                                manager.clearRecentTrains()
                                manager.clearViewedRecentTrains()
                                Haptics.play(.medium)
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                        }) {
                            ForEach(allRecentTrains.prefix(2)) { result in
                                let dummy = manager.createDummyTrain(from: result)
                                NavigationLink(destination: TrainStopsView(train: dummy, showCloseButton: false).onAppear {
                                    manager.addToRecentTrains(result)
                                    manager.addToViewedRecentTrains(number: result.number, description: result.description, departureTime: result.departureTime, arrivalTime: result.arrivalTime, category: result.category)
                                }) {
                                    RecentTrainHistoryRow(train: result)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        manager.removeRecentTrain(number: result.number)
                                        Haptics.play(.light)
                                    } label: {
                                        Label("Elimina", systemImage: "trash.fill")
                                    }
                                }
                            }
                        }
                    }
                    
                    if allRecentTrains.isEmpty && allRecentStations.isEmpty && nearbyStations.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary.opacity(0.6))
                            Text("Cerca Treni o Stazioni")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Inserisci il numero di un treno (es. 9604) oppure il nome di una stazione (es. Bologna Centrale).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .listRowBackground(Color.clear)
                    }
                } else {
                    if manager.searchResults.isEmpty && manager.searchStationResults.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "questionmark.folder")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("Nessun risultato")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Nessun treno o stazione trovato per \"\(query)\".")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .listRowBackground(Color.clear)
                    } else {
                        if !manager.searchResults.isEmpty {
                            Section(header: Text("Treni")) {
                                ForEach(manager.searchResults) { result in
                                    let dummy = manager.createDummyTrain(from: result)
                                    let timeStr: String? = {
                                        if let t = result.departureTime, !t.isEmpty, t != "--:--" { return t }
                                        if let fav = manager.favoriteTrains.first(where: { $0.number == result.number }), let t = fav.departureTime, !t.isEmpty, t != "--:--" { return t }
                                        if let tr = manager.trains.first(where: { $0.number == result.number }), !tr.time.isEmpty, tr.time != "--:--" { return tr.time }
                                        return nil
                                    }()
                                    NavigationLink(destination: TrainStopsView(train: dummy, showCloseButton: false).onAppear {
                                        manager.addToRecentTrains(result)
                                    }) {
                                        HStack(spacing: 12) {
                                            Image(systemName: "tram.fill")
                                                .foregroundColor(.blue)
                                                .font(.body)
                                                .frame(width: 24)
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 8) {
                                                    Text(String(format: String(localized: "Treno %@"), result.number))
                                                        .font(.headline)
                                                        .foregroundColor(.primary)
                                                    if let t = timeStr {
                                                        Text(t)
                                                            .font(.headline)
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                                Text(result.description.formattedStationName)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        let isLive = manager.activeLiveActivities.contains(result.number)
                                        Button {
                                            Task { _ = await manager.toggleQuickLiveActivity(for: result) }
                                        } label: {
                                            Label(
                                                isLive ? "Ferma Dynamic Island" : "Dynamic Island",
                                                systemImage: isLive ? "livephoto.slash" : "livephoto.play"
                                            )
                                        }
                                        .tint(isLive ? .red : .indigo)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        let isFav = manager.isFavorite(trainNumber: result.number)
                                        Button {
                                            manager.toggleFavorite(
                                                trainNumber: result.number,
                                                description: result.description,
                                                departureTime: timeStr
                                            )
                                            Haptics.play(.light)
                                        } label: {
                                            Label(
                                                isFav ? "Rimuovi dai preferiti" : "Preferito",
                                                systemImage: isFav ? "star.slash.fill" : "star.fill"
                                            )
                                        }
                                        .tint(isFav ? .red : .yellow)
                                    }
                                }
                            }
                        }
                        
                        if !manager.searchStationResults.isEmpty {
                            Section(header: Text("Stazioni")) {
                                ForEach(manager.searchStationResults) { result in
                                    let tempStation = manager.resolveStation(name: result.nomeLungo, fallbackVtID: result.vtID)
                                    NavigationLink(destination: SmartBoardView(station: tempStation).onAppear {
                                        manager.addToRecentStations(result)
                                        manager.addToViewedRecentStations(name: tempStation.name, vtID: tempStation.vtID ?? result.vtID)
                                    }) {
                                        HStack(spacing: 12) {
                                            Image(systemName: "building.2.crop.circle.fill")
                                                .foregroundColor(.orange)
                                                .font(.body)
                                                .frame(width: 24)
                                            
                                            Text(tempStation.name.formattedStationName)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                        }
                                        .padding(.vertical, 2)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        let isFav = manager.isMyStation(tempStation)
                                        Button {
                                            if isFav {
                                                manager.removeMyStation(tempStation)
                                            } else {
                                                manager.addMyStation(tempStation)
                                            }
                                            Haptics.play(.light)
                                        } label: {
                                            Label(
                                                isFav ? "Rimuovi dai preferiti" : "Preferito",
                                                systemImage: isFav ? "star.slash.fill" : "star.fill"
                                            )
                                        }
                                        .tint(isFav ? .red : .yellow)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
        }
        .onDisappear {
            searchTask?.cancel()
            searchTask = nil
            manager.isSearching = false
        }
        .onChange(of: query) { oldValue, newValue in
            searchTask?.cancel()
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 2 else {
                manager.searchResults = []
                manager.searchStationResults = []
                manager.isSearching = false
                return
            }
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                await manager.searchTrains(query: trimmed)
                guard !Task.isCancelled else { return }
                await manager.searchStations(query: trimmed)
            }
        }
    }
}

// MARK: - Metro Search View

struct MetroSearchView: View {
    @EnvironmentObject var metroManager: MetroManager
    @EnvironmentObject var locationManager: LocationManager
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    var onSelect: (MetroStation) -> Void
    
    var nearbyStations: [MetroStation] {
        guard let loc = locationManager.userLocation?.coordinate else { return [] }
        return metroManager.allStations
            .map { station -> (MetroStation, Double) in
                let dlat = station.latitude - loc.latitude
                let dlon = station.longitude - loc.longitude
                return (station, dlat*dlat + dlon*dlon)
            }
            .sorted(by: { $0.1 < $1.1 })
            .prefix(5)
            .map { $0.0 }
    }
    
    var body: some View {
        NavigationStack {
            List {
                let results = metroManager.search(query: query)
                
                if query.isEmpty {
                    let nearby = nearbyStations
                    if !nearby.isEmpty {
                        Section(header: Text("📍 Stazioni più vicine")) {
                            ForEach(nearby) { station in
                                stationRow(station)
                            }
                        }
                    }
                    
                    Section(header: Text("Tutte le Stazioni")) {
                        ForEach(results) { station in
                            stationRow(station)
                        }
                    }
                } else {
                    if results.isEmpty {
                        Text("Nessuna fermata metro trovata.")
                            .foregroundColor(.secondary)
                            .listRowBackground(Color.clear)
                    } else {
                        let nearbyMatching = nearbyStations.filter { station in
                            results.contains { $0.id == station.id }
                        }
                        let otherMatching = results.filter { station in
                            !nearbyMatching.contains { $0.id == station.id }
                        }
                        
                        if !nearbyMatching.isEmpty {
                            Section(header: Text("📍 Stazioni più vicine")) {
                                ForEach(nearbyMatching) { station in
                                    stationRow(station)
                                }
                            }
                        }
                        
                        if !otherMatching.isEmpty {
                            Section(header: Text("Altre Stazioni")) {
                                ForEach(otherMatching) { station in
                                    stationRow(station)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Cerca fermata metro...")
            .navigationTitle("Cerca Fermata Metro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Chiudi") { dismiss() }.fontWeight(.bold)
                }
            }
        }
    }
    
    @ViewBuilder
    private func stationRow(_ station: MetroStation) -> some View {
        Button {
            metroManager.addToRecent(station)
            onSelect(station)
            dismiss()
        } label: {
            HStack {
                let uLines = station.uniqueLines
                if uLines.count >= 2 {
                    Circle()
                        .fill(LinearGradient(stops: [.init(color: uLines[0].color, location: 0.5), .init(color: uLines[1].color, location: 0.5)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 12, height: 12)
                } else {
                    Circle()
                        .fill(station.color)
                        .frame(width: 12, height: 12)
                }
                
                Text(station.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                ForEach(uLines) { line in
                    let prefix = String(line.name.prefix(2))
                    Text(station.lineLabelWithBranch(prefix))
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(line.color.opacity(0.12))
                        .foregroundColor(line.color)
                        .cornerRadius(4)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Metro History Sheet

struct MetroHistorySheet: View {
    @EnvironmentObject var metroManager: MetroManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                if metroManager.recentStations.isEmpty {
                    Text("Nessuna stazione visitata di recente.")
                        .foregroundColor(.secondary)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(metroManager.recentStations) { station in
                        Button {
                            NotificationCenter.default.post(name: NSNotification.Name("OpenMetroStation"), object: station)
                            dismiss()
                        } label: {
                            HStack {
                                Circle()
                                    .fill(station.color)
                                    .frame(width: 10, height: 10)
                                Text(station.displayName)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Cronologia Metro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Chiudi") { dismiss() }.fontWeight(.bold)
                }
            }
        }
    }
}

