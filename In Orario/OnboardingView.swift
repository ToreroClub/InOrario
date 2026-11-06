import SwiftUI
import CoreLocation
import UserNotifications

enum OnboardingStep: String, CaseIterable, Identifiable {
    case welcome
    case region
    case passante
    case stations
    case features
    
    var id: String { rawValue }
}

struct OnboardingView: View {
    @Binding var showOnboarding: Bool
    @State private var currentStep: OnboardingStep = .welcome
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    
    private var activeSteps: [OnboardingStep] {
        var steps: [OnboardingStep] = [.welcome, .region]
        if manager.strikeRegion == "Lombardia" {
            steps.append(.passante)
        }
        steps.append(.stations)
        steps.append(.features)
        return steps
    }
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Barra superiore: indicatore step e pulsante Salta
                HStack {
                    // Indicatori di avanzamento a capsula
                    HStack(spacing: 6) {
                        ForEach(activeSteps) { step in
                            Capsule()
                                .fill(currentStep == step ? Color.blue : Color.secondary.opacity(0.25))
                                .frame(width: currentStep == step ? 22 : 7, height: 7)
                                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentStep)
                        }
                    }
                    
                    Spacer()
                    
                    Button("Salta") {
                        Haptics.play(.light)
                        completeOnboarding()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
                    .opacity(currentStep == activeSteps.last ? 0 : 1)
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 8)
                
                // Contenitore pagine
                TabView(selection: $currentStep) {
                    OnboardingWelcomeView(onContinue: {
                        requestPermissions()
                        advanceStep()
                    })
                    .tag(OnboardingStep.welcome)
                    
                    OnboardingRegionPickerView()
                    .tag(OnboardingStep.region)
                    
                    if manager.strikeRegion == "Lombardia" {
                        OnboardingPassanteLinePickerView()
                        .tag(OnboardingStep.passante)
                    }
                    
                    OnboardingStationsPreferenceView()
                    .tag(OnboardingStep.stations)
                    
                    OnboardingFeaturesView()
                    .tag(OnboardingStep.features)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                // Pulsante inferiore principale
                Button(action: {
                    handleForwardAction()
                }) {
                    HStack(spacing: 8) {
                        Text(buttonTitle)
                            .font(.headline)
                            .bold()
                        
                        Image(systemName: currentStep == activeSteps.last ? "arrow.right" : "chevron.right")
                            .font(.subheadline.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.blue.opacity(0.25), radius: 8, x: 0, y: 4)
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 20)
            }
        }
        .onChange(of: manager.strikeRegion) { _, newRegion in
            // Se la regione non è più Lombardia e siamo sul passante, passiamo a stazioni
            if newRegion != "Lombardia" && currentStep == .passante {
                currentStep = .stations
            }
        }
    }
    
    private var buttonTitle: String {
        if currentStep == activeSteps.last {
            return "Inizia a viaggiare"
        } else if currentStep == .welcome {
            return "Continua e autorizza"
        } else {
            return "Continua"
        }
    }
    
    private func handleForwardAction() {
        if currentStep == .welcome {
            requestPermissions()
            advanceStep()
        } else if currentStep == activeSteps.last {
            completeOnboarding()
        } else {
            Haptics.play(.medium)
            advanceStep()
        }
    }
    
    private func advanceStep() {
        let steps = activeSteps
        if let idx = steps.firstIndex(of: currentStep), idx < steps.count - 1 {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                currentStep = steps[idx + 1]
            }
        }
    }
    
    private func requestPermissions() {
        Haptics.play(.medium)
        locationManager.requestAuthorization()
        locationManager.requestLocation()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                if granted {
                    self.manager.remoteNotificationsEnabled = true
                    self.manager.strikeNotificationsEnabled = true
                    self.manager.saveFavorites()
                    UIApplication.shared.registerForRemoteNotifications()
                    self.manager.syncRemoteNotifications()
                }
            }
        }
    }
    
    private func completeOnboarding() {
        Haptics.play(.medium)
        withAnimation(.easeInOut(duration: 0.25)) {
            showOnboarding = false
        }
    }
}

// MARK: - Header Coordinato per Tutte le Schede
struct OnboardingHeaderView: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 76, height: 76)
                
                Image(systemName: icon)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(color)
            }
            .padding(.top, 4)
            
            Text(LocalizedStringKey(title))
                .font(.system(.title2, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            Text(LocalizedStringKey(subtitle))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
                .lineSpacing(2)
        }
    }
}

// MARK: - Scheda 1: Benvenuto & Permessi
struct OnboardingWelcomeView: View {
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            OnboardingHeaderView(
                icon: "train.side.front.car",
                color: .blue,
                title: "Benvenuto su In Orario",
                subtitle: "Il tuo compagno per viaggiare in treno con i dati ufficiali RFI, partenze e binari sempre aggiornati."
            )
            
            VStack(spacing: 14) {
                permissionRow(
                    icon: "location.fill",
                    color: .blue,
                    title: "Posizione",
                    desc: "Per rilevare la tua regione e mostrarti subito i tabelloni delle stazioni attorno a te."
                )
                
                permissionRow(
                    icon: "bell.badge.fill",
                    color: .orange,
                    title: "Notifiche & Live Activity",
                    desc: "Per seguire binario, ritardi e variazioni del treno direttamente sulla schermata di blocco."
                )
            }
            .padding(18)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .padding(.horizontal, 24)
            .padding(.top, 10)
            
            Spacer()
            Spacer()
        }
    }
    
    private func permissionRow(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Scheda 2: La Tua Regione
struct OnboardingRegionPickerView: View {
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var locationManager: LocationManager
    @State private var detectedRegion: String? = nil
    
    private let regions = [
        "Tutte", "Abruzzo", "Basilicata", "Calabria", "Campania",
        "Emilia-Romagna", "Friuli Venezia Giulia", "Lazio", "Liguria",
        "Lombardia", "Marche", "Molise", "Piemonte", "Puglia",
        "Sardegna", "Sicilia", "Toscana", "Trentino-Alto Adige",
        "Umbria", "Valle d'Aosta", "Veneto"
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            OnboardingHeaderView(
                icon: "map.fill",
                color: .red,
                title: "La Tua Regione",
                subtitle: "Ricevi scioperi, avvisi e notizie di circolazione rilevanti per la tua area geografica."
            )
            .padding(.top, 8)
            
            // Badge rilevamento GPS (se disponibile)
            if let detected = detectedRegion {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .foregroundColor(.green)
                        .font(.caption.bold())
                    Text("Rilevata dal GPS: \(detected)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    if manager.strikeRegion == detected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.subheadline)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.green.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 24)
            }
            
            // Lista selezioni regione con auto-scroll sul focus
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(regions, id: \.self) { region in
                            let isSelected = manager.strikeRegion == region
                            Button {
                                Haptics.play(.light)
                                manager.strikeRegion = region
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(region, anchor: .center)
                                }
                            } label: {
                                HStack {
                                    Text(region == "Tutte" ? "🇮🇹 Nazionale / Tutte le regioni" : region)
                                        .font(.subheadline.weight(isSelected ? .bold : .medium))
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.red)
                                            .font(.subheadline)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(isSelected ? Color.red.opacity(0.1) : Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(isSelected ? Color.red.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: isSelected ? 1.5 : 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                            .id(region)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 4)
                }
                .onChange(of: manager.strikeRegion) { _, newRegion in
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(newRegion, anchor: .center)
                    }
                }
                .onAppear {
                    tryDetectRegion()
                }
                .task {
                    if manager.strikeRegion != "Tutte" {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo(manager.strikeRegion, anchor: .center)
                        }
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
        .onAppear {
            tryDetectRegion()
        }
        .onChange(of: locationManager.userLocation) { _, _ in
            tryDetectRegion()
        }
    }
    
    private func tryDetectRegion() {
        guard let loc = locationManager.userLocation else { return }
        CLGeocoder().reverseGeocodeLocation(loc) { placemarks, _ in
            guard let admin = placemarks?.first?.administrativeArea else { return }
            let matched = regions.first {
                $0.localizedCaseInsensitiveCompare(admin) == .orderedSame ||
                admin.localizedCaseInsensitiveContains($0) ||
                $0.localizedCaseInsensitiveContains(admin)
            }
            if let matched = matched {
                DispatchQueue.main.async {
                    self.detectedRegion = matched
                    if self.manager.strikeRegion == "Tutte" {
                        self.manager.strikeRegion = matched
                    }
                }
            }
        }
    }
}

// MARK: - Scheda 3: Passante & Linee S (Lombardia)
struct OnboardingPassanteLinePickerView: View {
    @EnvironmentObject var passanteManager: PassanteManager
    @State private var previewLine: SuburbanLine? = nil
    
    private let columns = [
        GridItem(.adaptive(minimum: 70, maximum: 85), spacing: 10)
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            OnboardingHeaderView(
                icon: "tram.fill",
                color: .green,
                title: "Passante & Linee Suburbane",
                subtitle: "Seleziona le linee S di Milano e dintorni che prendi abitualmente per monitorarne partenze e regolarità."
            )
            .padding(.top, 8)
            
            // Griglia linee S
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(SuburbanData.shared.allLines) { line in
                    let isSelected = passanteManager.selectedSuburbanLines.contains(line.id)
                    Button {
                        Haptics.play(.light)
                        passanteManager.toggleSuburbanLine(line.id)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            previewLine = line
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(line.id)
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                            
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(isSelected ? line.color : Color(.secondarySystemGroupedBackground))
                        .foregroundColor(isSelected ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(line.color, lineWidth: isSelected ? 0 : 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 4)
            
            // Anteprima tracciato linea selezionata
            if let line = previewLine {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        HStack(spacing: 6) {
                            Text(line.id)
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(line.color)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                            
                            Text(line.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                        }
                        
                        Spacer()
                        
                        Text("\(line.stations.count) fermate")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    // Tracciato: Capolinea 1 -> Tratto Centrale -> Capolinea 2
                    HStack(alignment: .center, spacing: 6) {
                        // Capolinea 1
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Circle().fill(line.color).frame(width: 7, height: 7)
                                Text("Partenza")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.secondary)
                            }
                            Text(line.stations.first?.name.formattedStationName ?? "")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Connettore centrale
                        VStack(spacing: 3) {
                            HStack(spacing: 0) {
                                Rectangle()
                                    .fill(line.color.opacity(0.35))
                                    .frame(height: 2)
                                
                                Image(systemName: "tram.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(line.color)
                                    .padding(.horizontal, 4)
                                
                                Rectangle()
                                    .fill(line.color.opacity(0.35))
                                    .frame(height: 2)
                            }
                            
                            let isPassante = line.stations.contains(where: { $0.name.contains("Passante") || $0.name == "Porta Venezia" || $0.name == "Dateo" })
                            Text(isPassante ? "Passante Ferroviario" : "Tratto Urbano")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(line.color)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        
                        // Capolinea 2
                        VStack(alignment: .trailing, spacing: 3) {
                            HStack(spacing: 4) {
                                Text("Arrivo")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.secondary)
                                Circle().fill(line.color).frame(width: 7, height: 7)
                            }
                            Text(line.stations.last?.name.formattedStationName ?? "")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(line.color.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal, 24)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                    Text("Tocca una linea per selezionarla e visualizzarne il tracciato.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemGroupedBackground).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 24)
            }
            
            // Nota informativa
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text("Potrai sempre modificare le linee e le singole fermate nelle Impostazioni.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            
            Spacer(minLength: 0)
        }
        .onAppear {
            if previewLine == nil {
                previewLine = SuburbanData.shared.allLines.first(where: { passanteManager.selectedSuburbanLines.contains($0.id) }) ?? SuburbanData.shared.allLines.first
            }
        }
    }
}

// MARK: - Scheda 4: Stazioni Frequenti
struct OnboardingStationsPreferenceView: View {
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var locationManager: LocationManager
    @State private var showSearchSheet = false
    @State private var searchStationName = ""
    @State private var searchStationID = ""
    
    private var nearbyCandidates: [Station] {
        guard let userLoc = locationManager.userLocation else { return [] }
        let validCandidates = manager.allRFIStations.compactMap { st -> (station: RFIStation, dist: CLLocationDistance)? in
            guard let lat = st.lat, let lon = st.lon else { return nil }
            let loc = CLLocation(latitude: lat, longitude: lon)
            let dist = loc.distance(from: userLoc)
            return (st, dist)
        }
        let sorted = validCandidates.sorted { $0.dist < $1.dist }
        var results: [Station] = []
        for item in sorted.prefix(4) {
            let st = item.station
            results.append(Station(name: st.name, rfiID: st.rfiID, vtID: st.vtID, lat: st.lat, lon: st.lon))
        }
        return results
    }
    
    private var displayedCandidates: [Station] {
        if !nearbyCandidates.isEmpty {
            return nearbyCandidates
        }
        let region = manager.strikeRegion
        if region == "Lombardia" {
            return [
                manager.resolveStation(name: "Milano Centrale"),
                manager.resolveStation(name: "Milano Porta Garibaldi"),
                manager.resolveStation(name: "Milano Cadorna"),
                manager.resolveStation(name: "RHO FIERA")
            ]
        } else if region == "Lazio" {
            return [
                manager.resolveStation(name: "Roma Termini"),
                manager.resolveStation(name: "Roma Tiburtina"),
                manager.resolveStation(name: "Roma Ostiense"),
                manager.resolveStation(name: "Fiumicino Aeroporto")
            ]
        } else if region == "Piemonte" {
            return [
                manager.resolveStation(name: "Torino Porta Nuova"),
                manager.resolveStation(name: "Torino Porta Susa"),
                manager.resolveStation(name: "Novara"),
                manager.resolveStation(name: "Asti")
            ]
        } else {
            return [
                manager.resolveStation(name: "Milano Centrale"),
                manager.resolveStation(name: "Roma Termini"),
                manager.resolveStation(name: "Bologna Centrale"),
                manager.resolveStation(name: "Firenze Santa Maria Novella")
            ]
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            OnboardingHeaderView(
                icon: "star.fill",
                color: .orange,
                title: "Stazioni Frequenti",
                subtitle: "Salva le stazioni da cui parti più spesso per consultarne i tabelloni con un solo tocco."
            )
            .padding(.top, 8)
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    // Stazioni rilevate da GPS o suggerite per la regione selezionata
                    let candidates = displayedCandidates
                    if !candidates.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(nearbyCandidates.isEmpty ? "STAZIONI SUGGERITE" : "STAZIONI VICINE A TE")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                            
                            VStack(spacing: 8) {
                                ForEach(candidates) { station in
                                    let isFav = manager.isMyStation(station)
                                    HStack {
                                        Image(systemName: "building.2.crop.circle.fill")
                                            .foregroundColor(.orange)
                                            .font(.title3)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(station.name.formattedStationName)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundColor(.primary)
                                            
                                            if let lat = station.lat, let lon = station.lon, let userLoc = locationManager.userLocation {
                                                let d = userLoc.distance(from: CLLocation(latitude: lat, longitude: lon))
                                                let distStr = d < 1000 ? "\(Int(d))m da te" : String(format: "%.1fkm da te", d / 1000.0)
                                                Text(distStr)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        Button {
                                            Haptics.play(.medium)
                                            if isFav {
                                                manager.removeMyStation(station)
                                            } else {
                                                manager.addMyStation(station)
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: isFav ? "checkmark" : "plus")
                                                    .font(.caption.bold())
                                                Text(isFav ? "Aggiunta" : "Aggiungi")
                                                    .font(.caption.weight(.semibold))
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(isFav ? Color.blue.opacity(0.12) : Color(.tertiarySystemGroupedBackground))
                                            .foregroundColor(isFav ? .blue : .primary)
                                            .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }
                        }
                    }
                    
                    // Cerca un'altra stazione
                    Button {
                        showSearchSheet = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            Text("Cerca un'altra stazione...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 4)
            }
            
            Spacer(minLength: 0)
        }
        .sheet(isPresented: $showSearchSheet) {
            StationSelectionSheet(selectedName: $searchStationName, selectedID: $searchStationID, title: "Aggiungi Stazione", autoFocusSearch: true)
                .environmentObject(manager)
                .environmentObject(locationManager)
        }
        .onChange(of: searchStationID) { _, newID in
            guard !newID.isEmpty, !searchStationName.isEmpty else { return }
            let resolved = manager.resolveStation(name: searchStationName)
            manager.addMyStation(resolved)
            searchStationName = ""
            searchStationID = ""
        }
    }
}

// MARK: - Scheda 5: Funzioni Smart & Gestures
struct OnboardingFeaturesView: View {
    var body: some View {
        VStack(spacing: 16) {
            OnboardingHeaderView(
                icon: "sparkles",
                color: .purple,
                title: "Tutto Pronto per il Viaggio",
                subtitle: "Funzionalità avanzate per viaggiare in treno senza stress e senza sorprese."
            )
            .padding(.top, 8)
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    // Feature 1: Live Activity
                    featureCard(
                        icon: "iphone.circle.fill",
                        color: .purple,
                        title: "Live Activities & Isola Dinamica",
                        desc: "Segui ritardi, avanzamento e binario direttamente sulla schermata di blocco o nell'Isola Dinamica."
                    )
                    
                    // Feature 2: Coincidenze Metro con Pressione Prolungata
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.12))
                                    .frame(width: 38, height: 38)
                                Image(systemName: "hand.tap.fill")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.blue)
                            }
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Coincidenze Metro al Volo")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.primary)
                                Text("Dalla vista fermate del treno, tieni premuta una stazione per vedere le partenze metro e la stima di fattibilità del trasbordo.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineSpacing(2)
                            }
                        }
                        
                        // Badge interattivo esplicativo
                        HStack(spacing: 6) {
                            Text("👆 Pressione prolungata")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.12))
                                .foregroundColor(.blue)
                                .clipShape(Capsule())
                            
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 4) {
                                Circle().fill(Color.green).frame(width: 6, height: 6)
                                Text("Fattibilità trasbordo")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(Capsule())
                        }
                        .padding(.leading, 52)
                        .padding(.top, 2)
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                    )
                    
                    // Feature 3: Scioperi con IA
                    featureCard(
                        icon: "megaphone.fill",
                        color: .red,
                        title: "Scioperi & Notizie con IA",
                        desc: "Sintesi chiare e automatiche sugli avvisi di circolazione e agitazioni sindacali."
                    )
                    
                    // Feature 4: Widget Schermata Home
                    featureCard(
                        icon: "square.grid.2x2.fill",
                        color: .green,
                        title: "Widget Schermata Home",
                        desc: "Visualizza i tuoi treni e stazioni preferite a colpo d'occhio senza nemmeno aprire l'app."
                    )
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 4)
            }
            
            Spacer(minLength: 0)
        }
    }
    
    private func featureCard(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}
