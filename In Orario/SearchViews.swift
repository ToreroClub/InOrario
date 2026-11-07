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
                    Image(systemName: "train.side.front.car")
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
                    Label("Segui Treno (Live Activity)", systemImage: "clock.badge.checkmark.fill")
                }
                
                Button(action: {
                    let desc = "\(segment.origin) - \(segment.destination)"
                    manager.toggleFavorite(trainNumber: segment.trainNumber, description: desc, departureTime: segment.departureTime)
                    Haptics.play(.medium)
                }) {
                    let isFav = manager.favoriteTrains.contains(where: { $0.number == segment.trainNumber })
                    Label(isFav ? "Rimuovi dai Preferiti" : "Aggiungi ai Preferiti", systemImage: isFav ? "star.slash.fill" : "star.fill")
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
    let solution: TravelSolution
    
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
                Text("Tieni premuto su un treno per seguirlo o aggiungerlo ai Preferiti.")
            }
        }
        .navigationTitle("Dettagli Viaggio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                let isSaved = manager.isTripSaved(solution: solution)
                Button(action: {
                    withAnimation {
                        manager.toggleSavedTrip(solution: solution)
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        Text(isSaved ? "Salvato" : "Salva")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(isSaved ? .green : .blue)
                }
            }
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
    
    var isTravelOnly: Bool
    @State private var selectedTab: Int // 0: Treni e Stazioni, 1: Soluzioni
    
    init(isTravelOnly: Bool = false, initialTab: Int = 0) {
        self.isTravelOnly = isTravelOnly
        _selectedTab = State(initialValue: isTravelOnly ? 1 : initialTab)
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
    
    // TAB 1 State
    @State private var query = ""
    @State private var searchTask: Task<Void, Never>? = nil
    
    private var allRecentTrains: [SavedTrain] {
        Array(manager.unifiedRecentTrains.prefix(2))
    }
    
    private var allRecentStations: [VTSearchStation] {
        Array(manager.unifiedRecentStations.prefix(4))
    }
    
    private var nearbyStations: [Station] {
        guard let userLoc = locationManager.userLocation else { return [] }
        
        let validCandidates = manager.allRFIStations.compactMap { st -> (station: RFIStation, distance: CLLocationDistance)? in
            guard let lat = st.lat, let lon = st.lon else { return nil }
            let loc = CLLocation(latitude: lat, longitude: lon)
            let dist = loc.distance(from: userLoc)
            return (st, dist)
        }
        
        let sorted = validCandidates.sorted { $0.distance < $1.distance }
        
        var results: [Station] = []
        for item in sorted.prefix(3) {
            let st = item.station
            results.append(Station(name: st.name, rfiID: st.rfiID, vtID: st.vtID, lat: st.lat, lon: st.lon))
        }
        return results
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !isTravelOnly {
                    Picker("Sezione", selection: $selectedTab.animation(.easeInOut(duration: 0.2))) {
                        Text("Treni e Stazioni").tag(0)
                        Text("Soluzioni").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                    .background(Color(.systemGroupedBackground))
                    .onChange(of: selectedTab) { _, newValue in
                        Haptics.play(.light)
                        if newValue == 1 {
                            query = ""
                            manager.searchResults = []
                            manager.searchStationResults = []
                        }
                    }
                }
                
                if isTravelOnly || selectedTab == 1 {
                    travelSolutionsTab
                        .transition(.opacity)
                } else {
                    trainsAndStationsTab
                        .transition(.opacity)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(isTravelOnly ? "Cerca Viaggio" : "Cerca")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Chiudi") { dismiss() }
                        .fontWeight(.bold)
                }
            }
            .sheet(isPresented: $showOriginSearch) {
                StationSelectionSheet(selectedName: $originName, selectedID: $originID, title: "Stazione di Partenza")
            }
            .sheet(isPresented: $showDestSearch) {
                StationSelectionSheet(selectedName: $destName, selectedID: $destID, title: "Stazione di Arrivo")
            }
            .onAppear {
                if originID.isEmpty || destID.isEmpty {
                    manager.travelSolutions = []
                    hasSearchedSolutions = false
                }
                if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
                    locationManager.requestLocation()
                }
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
                                    hasSearchedSolutions = true
                                    Task {
                                        await manager.searchTravelSolutions(
                                            originID: originID,
                                            destID: destID,
                                            date: searchDate,
                                            originName: originName,
                                            destName: destName,
                                            onResolvedIDs: { newOrig, newDest in
                                                originID = newOrig
                                                destID = newDest
                                            }
                                        )
                                    }
                                } else {
                                    manager.travelSolutions = []
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
                        DatePicker("", selection: $searchDate, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "it_IT"))
                        
                        Spacer(minLength: 8)
                        
                        Button {
                            hasSearchedSolutions = true
                            Haptics.play(.medium)
                            Task {
                                await manager.searchTravelSolutions(
                                    originID: originID,
                                    destID: destID,
                                    date: searchDate,
                                    originName: originName,
                                    destName: destName,
                                    onResolvedIDs: { newOrig, newDest in
                                        originID = newOrig
                                        destID = newDest
                                    }
                                )
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(hasRouteBottom ? Color.blue : Color.blue.opacity(0.12))
                                    .frame(width: 42, height: 42)
                                
                                if manager.isSearchingSolutions {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.9)
                                } else {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(hasRouteBottom ? .white : .blue.opacity(0.4))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!hasRouteBottom || manager.isSearchingSolutions)
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
            } else if !originID.isEmpty && !destID.isEmpty && !manager.travelSolutions.isEmpty {
                Section(header: Text("Soluzioni Disponibili (\(manager.travelSolutions.count))")) {
                    ForEach(manager.travelSolutions) { solution in
                        NavigationLink(destination: TravelSolutionDetailsView(solution: solution)) {
                            TravelSolutionRow(solution: solution)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                withAnimation {
                                    manager.toggleSavedTrip(solution: solution)
                                }
                                Haptics.play(.medium)
                            } label: {
                                Label(
                                    manager.isTripSaved(solution: solution) ? "Rimuovi" : "Salva",
                                    systemImage: manager.isTripSaved(solution: solution) ? "bookmark.slash" : "bookmark.fill"
                                )
                            }
                            .tint(manager.isTripSaved(solution: solution) ? .red : .blue)
                        }
                    }
                }
            } else if hasSearchedSolutions && !originID.isEmpty && !destID.isEmpty {
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
            } else if !manager.favoriteRoutes.isEmpty {
                Section(header: Text("Le Mie Tratte Preferite")) {
                    ForEach(manager.favoriteRoutes) { route in
                        Button {
                            originName = route.originName
                            originID = route.originID
                            destName = route.destinationName
                            destID = route.destinationID
                            hasSearchedSolutions = true
                            Task {
                                await manager.searchTravelSolutions(
                                    originID: route.originID,
                                    destID: route.destinationID,
                                    date: searchDate,
                                    originName: route.originName,
                                    destName: route.destinationName,
                                    onResolvedIDs: { newOrig, newDest in
                                        originID = newOrig
                                        destID = newDest
                                    }
                                )
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.triangle.swap")
                                    .foregroundColor(.blue)
                                Text("\(route.originName) ➔ \(route.destinationName)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
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
                                let timeStr: String? = {
                                    if let t = result.departureTime, !t.isEmpty, t != "--:--" { return t }
                                    if let fav = manager.favoriteTrains.first(where: { $0.number == result.number }), let t = fav.departureTime, !t.isEmpty, t != "--:--" { return t }
                                    if let tr = manager.trains.first(where: { $0.number == result.number }), !tr.time.isEmpty, tr.time != "--:--" { return tr.time }
                                    return nil
                                }()
                                NavigationLink(destination: TrainStopsView(train: dummy, showCloseButton: false).onAppear {
                                    manager.addToRecentTrains(result)
                                    manager.addToViewedRecentTrains(number: result.number, description: result.description, departureTime: result.departureTime)
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "train.side.front.car")
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
                                            Image(systemName: "train.side.front.car")
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
                                    .swipeActions(edge: .trailing) {
                                        if let vtID = tempStation.vtID, !vtID.isEmpty {
                                            Button {
                                                if manager.isMyStation(vtID: vtID) {
                                                    manager.removeMyStation(vtID: vtID)
                                                } else {
                                                    manager.addMyStation(name: tempStation.name, vtID: vtID)
                                                }
                                                Haptics.play(.light)
                                            } label: {
                                                Label(manager.isMyStation(vtID: vtID) ? "Rimuovi dai Preferiti" : "Aggiungi ai Preferiti", systemImage: manager.isMyStation(vtID: vtID) ? "star.slash" : "star.fill")
                                            }
                                            .tint(.orange)
                                        }
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

