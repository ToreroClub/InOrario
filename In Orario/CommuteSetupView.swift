import SwiftUI

struct CommuteSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var passanteManager: PassanteManager
    @EnvironmentObject var cache: MetroCache
    @EnvironmentObject var usageTracker: UsageTracker
    @StateObject private var commuteManager = SupporterCommuteManager.shared
    
    @State private var origins: [String] = []
    @State private var destinations: [String] = []
    @State private var defaultOutboundBand: String = "07:00 - 08:00"
    @State private var defaultReturnBand: String = "17:00 - 18:00"
    @State private var selectedWeekdays: Set<Int> = [1, 2, 3, 4, 5] // Lun - Ven
    @State private var customizePerDay: Bool = false
    @State private var daySchedules: [Int: DayCommuteSchedule] = [:]
    @State private var proactiveAlerts: Bool = true
    
    // Station Pickers
    @State private var showOriginPicker: Bool = false
    @State private var showDestPicker: Bool = false
    @State private var tempOriginName: String = ""
    @State private var tempOriginID: String = ""
    @State private var tempDestName: String = ""
    @State private var tempDestID: String = ""
    
    // Simulation
    @State private var simulationTripType: Bool = false // false = andata, true = ritorno
    @State private var isSaving: Bool = false
    @State private var showPlanBSheet: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    
    let weekdayNames = [
        (1, "Lun", "Lunedì"),
        (2, "Mar", "Martedì"),
        (3, "Mer", "Mercoledì"),
        (4, "Gio", "Giovedì"),
        (5, "Ven", "Venerdì"),
        (6, "Sab", "Sabato"),
        (7, "Dom", "Domenica")
    ]
    
    var body: some View {
        Form {
            // Header pulito
            Section {
                Text("Il server monitora la tua tratta abituale e in caso di cancellazioni o gravi ritardi riceverai un'alternativa.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 2)
            }
            
            // STAZIONI DI PARTENZA
            Section(header: Text("Stazioni di partenza")) {
                if origins.isEmpty {
                    Text("Nessuna stazione di partenza impostata")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(origins, id: \.self) { st in
                        HStack {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundColor(.blue)
                            Text(st)
                                .font(.body)
                            Spacer()
                            Button {
                                origins.removeAll { $0 == st }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                
                Button {
                    showOriginPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                        Text("Aggiungi stazione di partenza...")
                            .foregroundColor(.blue)
                    }
                }
            }
            
            // STAZIONI DI ARRIVO
            Section(header: Text("Stazioni di arrivo")) {
                if destinations.isEmpty {
                    Text("Nessuna stazione di arrivo impostata")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(destinations, id: \.self) { st in
                        HStack {
                            Image(systemName: "flag.fill")
                                .foregroundColor(.green)
                            Text(st)
                                .font(.body)
                            Spacer()
                            Button {
                                destinations.removeAll { $0 == st }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                
                Button {
                    showDestPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                        Text("Aggiungi stazione di arrivo...")
                            .foregroundColor(.green)
                    }
                }
            }
            
            // ORARI E GIORNI DI VIAGGIO (SCHEDA UNICA)
            Section(header: Text("Orari di viaggio")) {
                Toggle("Personalizza per singolo giorno", isOn: $customizePerDay.animation(.easeInOut(duration: 0.2)))
                
                if !customizePerDay {
                    Picker("Andata", selection: $defaultOutboundBand) {
                        ForEach(SupporterCommuteManager.timeBands, id: \.self) { band in
                            Text(band).tag(band)
                        }
                    }
                    
                    Picker("Ritorno", selection: $defaultReturnBand) {
                        ForEach(SupporterCommuteManager.timeBands, id: \.self) { band in
                            Text(band).tag(band)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Giorni di viaggio")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 6) {
                            ForEach(weekdayNames, id: \.0) { day, shortName, _ in
                                let isSelected = selectedWeekdays.contains(day)
                                Button {
                                    Haptics.play(.light)
                                    if isSelected {
                                        if selectedWeekdays.count > 1 {
                                            selectedWeekdays.remove(day)
                                        }
                                    } else {
                                        selectedWeekdays.insert(day)
                                    }
                                } label: {
                                    Text(shortName)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(isSelected ? Color.blue : Color(.tertiarySystemFill))
                                        .foregroundColor(isSelected ? .white : .primary)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(weekdayNames, id: \.0) { dayIndex, shortName, fullName in
                        let isEnabled = daySchedules[dayIndex]?.isEnabled ?? true
                        let outbound = daySchedules[dayIndex]?.outboundBand ?? defaultOutboundBand
                        let ret = daySchedules[dayIndex]?.returnBand ?? defaultReturnBand
                        
                        HStack(alignment: .center, spacing: 10) {
                            Button {
                                Haptics.play(.light)
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    var cur = daySchedules[dayIndex] ?? DayCommuteSchedule(
                                        isEnabled: false,
                                        outboundBand: defaultOutboundBand,
                                        returnBand: defaultReturnBand
                                    )
                                    cur.isEnabled.toggle()
                                    daySchedules[dayIndex] = cur
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 13, weight: .bold))
                                    Text(fullName)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isEnabled ? Color.blue.opacity(0.15) : Color(.tertiarySystemFill))
                                .foregroundColor(isEnabled ? .blue : .secondary)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            
                            Spacer()
                            
                            if !isEnabled {
                                Text("Nessun viaggio")
                                    .font(.footnote)
                                    .foregroundColor(.secondary.opacity(0.6))
                                    .strikethrough(true, color: .secondary.opacity(0.5))
                                    .padding(.trailing, 4)
                            } else {
                                VStack(alignment: .trailing, spacing: 4) {
                                    Menu {
                                        ForEach(SupporterCommuteManager.timeBands, id: \.self) { band in
                                            Button {
                                                var cur = daySchedules[dayIndex] ?? DayCommuteSchedule()
                                                cur.outboundBand = band
                                                daySchedules[dayIndex] = cur
                                            } label: {
                                                HStack {
                                                    Text(band)
                                                    if band == outbound {
                                                        Image(systemName: "checkmark")
                                                    }
                                                }
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text("Andata:")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            Text(outbound)
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.primary)
                                            Image(systemName: "chevron.up.chevron.down")
                                                .font(.system(size: 7))
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Color(.tertiarySystemFill))
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Menu {
                                        ForEach(SupporterCommuteManager.timeBands, id: \.self) { band in
                                            Button {
                                                var cur = daySchedules[dayIndex] ?? DayCommuteSchedule()
                                                cur.returnBand = band
                                                daySchedules[dayIndex] = cur
                                            } label: {
                                                HStack {
                                                    Text(band)
                                                    if band == ret {
                                                        Image(systemName: "checkmark")
                                                    }
                                                }
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text("Ritorno:")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            Text(ret)
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.primary)
                                            Image(systemName: "chevron.up.chevron.down")
                                                .font(.system(size: 7))
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Color(.tertiarySystemFill))
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            
            // VERIFICA ALTERNATIVE (CON SELEZIONE ANDATA / RITORNO)
            Section(header: Text("Verifica alternative")) {
                Picker("Direzione", selection: $simulationTripType) {
                    Text("Andata").tag(false)
                    Text("Ritorno").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 2)
                
                Button {
                    Task {
                        commuteManager.activePlanB = nil
                        await saveSettings()
                        let loc = await locationManager.getCurrentLocation(maxAge: 30)
                        let coord = loc?.coordinate
                        await commuteManager.requestManualPlanB(
                            origins: origins,
                            destinations: destinations,
                            for: simulationTripType,
                            userLat: coord?.latitude,
                            userLon: coord?.longitude
                        )
                        if commuteManager.activePlanB != nil {
                            showPlanBSheet = true
                        } else if let err = commuteManager.lastSyncError {
                            errorMessage = err
                            showErrorAlert = true
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.swap")
                        Text("Verifica alternative adesso")
                        if commuteManager.isCalculatingPlanB {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(origins.isEmpty || destinations.isEmpty || commuteManager.isCalculatingPlanB)
            }
        }
        .navigationTitle("Abitudini di viaggio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva") {
                    Task {
                        await saveSettings()
                        dismiss()
                    }
                }
                .fontWeight(.bold)
                .disabled(origins.isEmpty || destinations.isEmpty || isSaving)
            }
        }
        .onAppear {
            loadInitialState()
        }
        // Station Search Sheet: Origine
        .sheet(isPresented: $showOriginPicker) {
            StationSelectionSheet(
                selectedName: $tempOriginName,
                selectedID: $tempOriginID,
                title: "Stazione di partenza",
                autoFocusSearch: true
            )
            .environmentObject(manager)
            .environmentObject(locationManager)
        }
        .onChange(of: tempOriginName) { _, newName in
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !origins.contains(trimmed) {
                origins.append(trimmed)
            }
            tempOriginName = ""
            tempOriginID = ""
        }
        // Station Search Sheet: Arrivo
        .sheet(isPresented: $showDestPicker) {
            StationSelectionSheet(
                selectedName: $tempDestName,
                selectedID: $tempDestID,
                title: "Stazione di arrivo",
                autoFocusSearch: true
            )
            .environmentObject(manager)
            .environmentObject(locationManager)
        }
        .onChange(of: tempDestName) { _, newName in
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !destinations.contains(trimmed) {
                destinations.append(trimmed)
            }
            tempDestName = ""
            tempDestID = ""
        }
        // Modal Alternative
        .sheet(isPresented: $showPlanBSheet) {
            if let plan = commuteManager.activePlanB {
                NavigationStack {
                    PlanBDetailView(plan: plan)
                        .environmentObject(manager)
                        .environmentObject(passanteManager)
                        .environmentObject(locationManager)
                        .environmentObject(cache)
                        .environmentObject(usageTracker)
                }
            }
        }
        .alert("Errore verifica", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func loadInitialState() {
        origins = commuteManager.origins
        destinations = commuteManager.destinations
        defaultOutboundBand = commuteManager.defaultOutboundBand
        defaultReturnBand = commuteManager.defaultReturnBand
        selectedWeekdays = commuteManager.activeWeekdays
        customizePerDay = commuteManager.customizePerDay
        daySchedules = commuteManager.daySchedules
        proactiveAlerts = commuteManager.proactiveAlertsEnabled
        
        // Se nel pomeriggio/sera (dalle 13 in poi), seleziona di default il ritorno per la simulazione
        let currentHour = Calendar.current.component(.hour, from: Date())
        simulationTripType = (currentHour >= 13)
        
        if daySchedules.isEmpty {
            applyGeneralTimesToDays()
        }
    }
    
    private func applyGeneralTimesToDays() {
        var dict: [Int: DayCommuteSchedule] = [:]
        for (dayIndex, _, _) in weekdayNames {
            let isSelected = selectedWeekdays.contains(dayIndex)
            dict[dayIndex] = DayCommuteSchedule(
                isEnabled: isSelected,
                outboundBand: defaultOutboundBand,
                returnBand: defaultReturnBand
            )
        }
        daySchedules = dict
    }
    
    private func saveSettings() async {
        isSaving = true
        defer { isSaving = false }
        
        commuteManager.origins = origins
        commuteManager.destinations = destinations
        commuteManager.defaultOutboundBand = defaultOutboundBand
        commuteManager.defaultReturnBand = defaultReturnBand
        commuteManager.activeWeekdays = selectedWeekdays
        commuteManager.customizePerDay = customizePerDay
        commuteManager.daySchedules = daySchedules
        commuteManager.proactiveAlertsEnabled = proactiveAlerts
        
        await commuteManager.syncRoutineWithServer()
    }
}

// MARK: - Plan B Detail View (Native SF Symbols & iOS UI)

struct PlanBDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var cache: MetroCache
    @EnvironmentObject var usageTracker: UsageTracker
    @ObservedObject private var commuteManager = SupporterCommuteManager.shared
    
    let plan: PlanBReportDTO
    var initialFocusedAlternativeId: String? = nil
    @State private var selectedDetailTrain: Train? = nil
    @State private var selectedOriginStation: String? = nil
    
    private var currentPlan: PlanBReportDTO {
        commuteManager.activePlanB ?? plan
    }
    
    private var nearestOrigin: (name: String, distance: Double)? {
        guard let nearest = locationManager.findNearestStation(among: currentPlan.origins) else { return nil }
        let cleanName = nearest.name.localizedCaseInsensitiveContains("Garibaldi") ? "Milano Porta Garibaldi" : nearest.name
        return (cleanName, nearest.distance)
    }
    
    private var sortedOrigins: [String] {
        var unique: [String] = []
        for orig in currentPlan.origins {
            let normalized = orig.localizedCaseInsensitiveContains("Garibaldi") ? "Milano Porta Garibaldi" : orig
            if !unique.contains(where: { isStationMatch($0, normalized) }) {
                unique.append(normalized)
            }
        }
        guard let nearest = nearestOrigin?.name else { return unique }
        unique.sort { a, b in
            let aIsNearest = isStationMatch(a, nearest)
            let bIsNearest = isStationMatch(b, nearest)
            if aIsNearest && !bIsNearest { return true }
            if !aIsNearest && bIsNearest { return false }
            return false
        }
        return unique
    }
    
    private func isStationMatch(_ s1: String, _ s2: String) -> Bool {
        if s1.localizedCaseInsensitiveCompare(s2) == .orderedSame { return true }
        let l1 = s1.lowercased()
        let l2 = s2.lowercased()
        if l1.contains("garibaldi") && l2.contains("garibaldi") &&
           !l1.contains("pavia") && !l2.contains("pavia") &&
           !l1.contains("casalecchio") && !l2.contains("casalecchio") &&
           !l1.contains("napoli") && !l2.contains("napoli") {
            return true
        }
        if s1.localizedCaseInsensitiveContains(s2) || s2.localizedCaseInsensitiveContains(s1) { return true }
        func clean(_ s: String) -> String {
            var str = s.uppercased()
            for w in ["MILANO ", "ROMA ", "NAPOLI ", "TORINO ", "BOLOGNA ", "FIRENZE ", "PASSANTE", "SUPERFICIE", "SOTTERRANEA", "SOTTERRANEO", "SOTT.", "FS", "F.S.", "POLITECNICO", "PORTA ", "P.TA ", "P. ", "P "] {
                str = str.replacingOccurrences(of: w, with: "")
            }
            return str.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let c1 = clean(s1)
        let c2 = clean(s2)
        return !c1.isEmpty && !c2.isEmpty && c1 == c2
    }
    
    private var displayedAlternatives: [PlanBAlternativeItem] {
        if let sel = selectedOriginStation {
            return currentPlan.alternatives.filter { alt in
                isStationMatch(alt.station, sel)
            }
        }
        return currentPlan.alternatives
    }
    
    private func formatDistanceText(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters)) m"
        } else {
            return String(format: "%.1f km", meters / 1000.0)
        }
    }
    
    private func reloadAlternatives() async {
        let loc = await locationManager.getCurrentLocation(maxAge: 30)
        let coord = loc?.coordinate
        let isReturn = currentPlan.origins.contains { orig in
            commuteManager.destinations.contains { $0.localizedCaseInsensitiveContains(orig) || orig.localizedCaseInsensitiveContains($0) }
        }
        await commuteManager.requestManualPlanB(for: isReturn, userLat: coord?.latitude, userLon: coord?.longitude)
    }
    
    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                // Selettore interattivo stazioni di partenza
                if currentPlan.origins.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Stazione di partenza")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                // Opzione "Tutte"
                                Button {
                                    Haptics.play(.light)
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedOriginStation = nil
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text("Tutte")
                                            .font(.subheadline)
                                            .fontWeight(selectedOriginStation == nil ? .bold : .medium)
                                        Text("(\(currentPlan.alternatives.count))")
                                            .font(.caption2)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(selectedOriginStation == nil ? Color.orange : Color(.secondarySystemGroupedBackground))
                                    .foregroundColor(selectedOriginStation == nil ? .white : .primary)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                
                                ForEach(sortedOrigins, id: \.self) { st in
                                    let isSelected = selectedOriginStation != nil && isStationMatch(selectedOriginStation!, st)
                                    let isNearest = nearestOrigin != nil && isStationMatch(nearestOrigin!.name, st)
                                    let count = currentPlan.alternatives.filter { isStationMatch($0.station, st) }.count
                                    
                                    Button {
                                        Haptics.play(.light)
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedOriginStation = isSelected ? nil : st
                                        }
                                    } label: {
                                        HStack(spacing: 5) {
                                            if isNearest {
                                                Image(systemName: "location.fill")
                                                    .font(.caption2)
                                                    .foregroundColor(isSelected ? .white : .blue)
                                            }
                                            Text(st)
                                                .font(.subheadline)
                                                .fontWeight(isSelected ? .bold : .medium)
                                            
                                            if isNearest, let dist = nearestOrigin?.distance {
                                                Text("(\(formatDistanceText(dist)))")
                                                    .font(.caption2)
                                                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                                            }
                                            Text("(\(count))")
                                                .font(.caption2)
                                                .foregroundColor(isSelected ? .white.opacity(0.8) : (count == 0 ? .secondary.opacity(0.6) : .secondary))
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(isSelected ? Color.blue : Color(.secondarySystemGroupedBackground))
                                        .foregroundColor(isSelected ? .white : (count == 0 ? .secondary : .primary))
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                } else if let nearest = nearestOrigin {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("Partenza da **\(currentPlan.origins[0])** (a \(formatDistanceText(nearest.distance)))")
                            .font(.caption)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.horizontal)
                }
                
                // Opzioni verificate
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Opzioni disponibili")
                            .font(.headline)
                        Spacer()
                        if let sel = selectedOriginStation {
                            Text("Filtro: \(sel)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    
                    if displayedAlternatives.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "tram.slash")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary.opacity(0.6))
                                .padding(.top, 16)
                            if let sel = selectedOriginStation {
                                Text("Nessuna corsa diretta trovata da \(sel).")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("I treni per la tua destinazione partono dalle altre stazioni configurate.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 28)
                                Button {
                                    withAnimation { selectedOriginStation = nil }
                                } label: {
                                    Text("Mostra tutte le stazioni")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.blue)
                                        .cornerRadius(8)
                                }
                                .padding(.top, 4)
                            } else {
                                Text("Nessuna soluzione trovata.")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("Verifica le stazioni impostate o riprova a verificare tra qualche minuto.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 28)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(Array(displayedAlternatives.enumerated()), id: \.element.id) { index, alt in
                            let isChosen = commuteManager.chosenAlternativeId == alt.id
                            let isNearest = nearestOrigin != nil && alt.station.localizedCaseInsensitiveContains(nearestOrigin!.name)
                            let legsToDisplay: [PlanBLegItem] = {
                                if let l = alt.legs, !l.isEmpty {
                                    let cleaned = l.filter { leg in
                                        !isStationMatch(leg.origin, leg.destination)
                                    }
                                    if !cleaned.isEmpty { return cleaned }
                                }
                                return [
                                    PlanBLegItem(
                                        train_number: alt.train_number,
                                        category: alt.category,
                                        origin: alt.station,
                                        destination: alt.destination,
                                        departure_time: alt.departure_time,
                                        arrival_time: alt.arrival_time ?? "--:--",
                                        delay: alt.delay,
                                        platform: alt.platform,
                                        is_urban: alt.train_number.contains("M1") || alt.category.contains("Metro"),
                                        is_station_walk: false,
                                        travel_minutes: nil,
                                        urban_headsign: nil
                                    )
                                ]
                            }()
                            let isDirect = legsToDisplay.count <= 1
                            
                            VStack(alignment: .leading, spacing: 12) {
                                // Header: Opzione, badge e durata totale
                                HStack {
                                    HStack(spacing: 6) {
                                        Text("OPZIONE \(index + 1)")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(index == 0 ? Color.green.opacity(0.18) : Color.blue.opacity(0.18))
                                            .foregroundColor(index == 0 ? .green : .blue)
                                            .cornerRadius(6)
                                        
                                        if isDirect {
                                            Text("DIRETTO")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(Color.green.opacity(0.18))
                                                .foregroundColor(.green)
                                                .cornerRadius(6)
                                        }
                                        
                                        if isNearest {
                                            HStack(spacing: 3) {
                                                Image(systemName: "location.fill")
                                                    .font(.system(size: 8, weight: .bold))
                                                Text("PIÙ VICINA")
                                                    .font(.system(size: 9, weight: .bold))
                                            }
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.blue.opacity(0.18))
                                            .foregroundColor(.blue)
                                            .cornerRadius(6)
                                        }
                                        
                                        if isChosen {
                                            HStack(spacing: 3) {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 8, weight: .bold))
                                                Text("SEGUITO")
                                                    .font(.system(size: 9, weight: .bold))
                                            }
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.orange.opacity(0.18))
                                            .foregroundColor(.orange)
                                            .cornerRadius(6)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    if let dur = alt.duration, !dur.isEmpty {
                                        Text(dur)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                // Tratta complessiva: Da -> A pulita e leggibile
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(legsToDisplay.first?.origin ?? alt.station)
                                            .font(.headline)
                                            .fontWeight(.bold)
                                            .lineLimit(1)
                                        Text(legsToDisplay.first?.departure_time ?? alt.departure_time)
                                            .font(.title2)
                                            .fontWeight(.heavy)
                                            .foregroundColor(alt.delay > 0 ? .orange : .green)
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(spacing: 2) {
                                        Image(systemName: "arrow.right")
                                            .font(.caption.bold())
                                            .foregroundColor(.secondary)
                                        Text(isDirect ? "Diretto" : "\(legsToDisplay.count - 1) cambi")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(isDirect ? .green : .secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(alt.destination)
                                            .font(.headline)
                                            .fontWeight(.bold)
                                            .lineLimit(1)
                                            .multilineTextAlignment(.trailing)
                                        Text(alt.arrival_time ?? "--:--")
                                            .font(.title2)
                                            .fontWeight(.heavy)
                                            .foregroundColor(.primary)
                                    }
                                }
                                .padding(.vertical, 2)
                                
                                Divider()
                                
                                // Treni del Viaggio in ordine cronologico esatto
                                VStack(spacing: 8) {
                                    ForEach(Array(legsToDisplay.enumerated()), id: \.element.id) { legIdx, leg in
                                        let isWalk = leg.is_station_walk == true || leg.category.contains("piedi") || leg.train_number.contains("piedi")
                                        let isRailTrain = !isWalk && !leg.is_urban
                                        let cleanCat = cleanTrainCategory(leg.category)
                                        let displayCatNum = cleanCat.isEmpty ? leg.train_number : "\(cleanCat) \(leg.train_number)"
                                        
                                        if isRailTrain {
                                            Button {
                                                Haptics.play(.light)
                                                selectedDetailTrain = Train(
                                                    category: cleanCat,
                                                    number: leg.train_number,
                                                    destination: leg.destination,
                                                    time: leg.departure_time,
                                                    delay: leg.delay > 0 ? "+\(leg.delay)'" : "0",
                                                    platform: leg.platform
                                                )
                                            } label: {
                                                VStack(alignment: .leading, spacing: 6) {
                                                    HStack {
                                                        Image(systemName: "train.side.front.car")
                                                            .foregroundColor(.blue)
                                                        Text(displayCatNum)
                                                            .font(.subheadline)
                                                            .fontWeight(.bold)
                                                            .foregroundColor(.primary)
                                                        
                                                        Spacer()
                                                        
                                                        if leg.delay > 0 {
                                                            Text("ritardo \(leg.delay) min.")
                                                                .font(.caption2)
                                                                .fontWeight(.bold)
                                                                .foregroundColor(.red)
                                                                .padding(.horizontal, 6)
                                                                .padding(.vertical, 2)
                                                                .background(Color.red.opacity(0.18))
                                                                .cornerRadius(4)
                                                        } else {
                                                            Text("in orario")
                                                                .font(.caption2)
                                                                .fontWeight(.bold)
                                                                .foregroundColor(.green)
                                                                .padding(.horizontal, 6)
                                                                .padding(.vertical, 2)
                                                                .background(Color.green.opacity(0.18))
                                                                .cornerRadius(4)
                                                        }
                                                        
                                                        if !leg.platform.isEmpty && leg.platform != "--" {
                                                            Text("Bin. \(leg.platform)")
                                                                .font(.caption2.bold())
                                                                .padding(.horizontal, 6)
                                                                .padding(.vertical, 2)
                                                                .background(Color(.tertiarySystemFill))
                                                                .cornerRadius(4)
                                                        }
                                                        
                                                        Image(systemName: "chevron.right")
                                                            .font(.system(size: 11, weight: .semibold))
                                                            .foregroundColor(.blue)
                                                    }
                                                    
                                                    HStack {
                                                        VStack(alignment: .leading, spacing: 2) {
                                                            Text("Da: \(leg.origin)").font(.caption).foregroundColor(.secondary)
                                                            Text("A: \(leg.destination)").font(.caption).foregroundColor(.secondary)
                                                        }
                                                        Spacer()
                                                        VStack(alignment: .trailing, spacing: 2) {
                                                            Text(leg.departure_time).font(.caption).fontWeight(.bold)
                                                            Text(leg.arrival_time).font(.caption).fontWeight(.bold)
                                                        }
                                                    }
                                                }
                                                .padding(10)
                                                .background(Color.blue.opacity(0.08))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 10)
                                                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                                                )
                                                .cornerRadius(10)
                                            }
                                            .buttonStyle(.plain)
                                        } else {
                                            VStack(alignment: .leading, spacing: 6) {
                                                HStack {
                                                    if isWalk {
                                                        Image(systemName: "figure.walk")
                                                            .foregroundColor(.orange)
                                                        Text("Interscambio a piedi")
                                                            .font(.subheadline)
                                                            .fontWeight(.bold)
                                                            .foregroundColor(.primary)
                                                    } else {
                                                        Image(systemName: "tram.fill")
                                                            .foregroundColor(.purple)
                                                        Text(leg.category.hasPrefix("Metro") ? leg.category : "\(leg.category) \(leg.train_number)")
                                                            .font(.subheadline)
                                                            .fontWeight(.bold)
                                                            .foregroundColor(.primary)
                                                    }
                                                    
                                                    Spacer()
                                                    
                                                    if isWalk {
                                                        Text("\(leg.travel_minutes ?? 1) min a piedi")
                                                            .font(.caption2.bold())
                                                            .foregroundColor(.orange)
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(Color.orange.opacity(0.15))
                                                            .cornerRadius(4)
                                                    } else {
                                                        Text("\(leg.travel_minutes ?? 15) min stimati")
                                                            .font(.caption2.bold())
                                                            .foregroundColor(.purple)
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(Color.purple.opacity(0.15))
                                                            .cornerRadius(4)
                                                    }
                                                }
                                                
                                                HStack {
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text("Da: \(leg.origin)").font(.caption).foregroundColor(.secondary)
                                                        Text("A: \(leg.destination)").font(.caption).foregroundColor(.secondary)
                                                        if let headsign = leg.urban_headsign, !headsign.isEmpty {
                                                            Text("Dir. \(headsign)").font(.caption2.bold()).foregroundColor(.purple)
                                                        }
                                                    }
                                                    Spacer()
                                                    VStack(alignment: .trailing, spacing: 2) {
                                                        Text(leg.departure_time).font(.caption).fontWeight(.bold)
                                                        Text(leg.arrival_time).font(.caption).fontWeight(.bold)
                                                    }
                                                }
                                            }
                                            .padding(10)
                                            .background(Color(.tertiarySystemGroupedBackground).opacity(0.7))
                                            .cornerRadius(10)
                                        }
                                        
                                        if legIdx < legsToDisplay.count - 1 {
                                            HStack {
                                                Spacer()
                                                Image(systemName: "arrow.down")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary.opacity(0.6))
                                                Text("Interscambio")
                                                    .font(.system(size: 10, weight: .medium))
                                                    .foregroundColor(.secondary.opacity(0.8))
                                                Spacer()
                                            }
                                        }
                                    }
                                }
                                
                                Divider()
                                
                                // Azioni individuali per questa opzione
                                Button {
                                    Haptics.play(.medium)
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        commuteManager.toggleChosenAlternative(id: alt.id)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 14, weight: .semibold))
                                        Text(isChosen ? "Seguito" : "Segui")
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(isChosen ? Color.orange.opacity(0.18) : Color(.tertiarySystemFill))
                                    .foregroundColor(isChosen ? .orange : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding()
                            .background(isChosen ? Color.orange.opacity(0.06) : Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(isChosen ? Color.orange : (index == 0 ? Color.green.opacity(0.4) : Color.clear), lineWidth: isChosen ? 2 : 1)
                            )
                            .padding(.horizontal)
                            .id(alt.id)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .onAppear {
            locationManager.requestLocation()
            scrollToChosenAlternative(using: scrollProxy)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Alternative di viaggio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(.secondarySystemFill))
                            .frame(width: 30, height: 30)
                        Image(systemName: "multiply")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.primary)
                    }
                }
                .buttonStyle(.plain)
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.play(.light)
                    Task {
                        await reloadAlternatives()
                    }
                } label: {
                    if commuteManager.isCalculatingPlanB {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(commuteManager.isCalculatingPlanB)
            }
        }
        .sheet(item: $selectedDetailTrain) { t in
            NavigationStack {
                TrainStopsView(train: t, showCloseButton: true)
                    .environmentObject(manager)
                    .environmentObject(passanteManager)
                    .environmentObject(locationManager)
                    .environmentObject(cache)
                    .environmentObject(usageTracker)
            }
        }
    }
}

    private func scrollToChosenAlternative(using proxy: ScrollViewProxy) {
        let targetId = initialFocusedAlternativeId ?? commuteManager.chosenAlternativeId
        guard let targetId = targetId else { return }
        
        let chosenAlt = currentPlan.alternatives.first(where: {
            $0.id == targetId ||
            targetId.hasPrefix("\($0.train_number)_\($0.departure_time)") ||
            $0.id.hasPrefix(targetId.components(separatedBy: "_").prefix(2).joined(separator: "_"))
        })
        guard let target = chosenAlt else { return }
        
        // Se c'è un filtro stazione che nasconde l'alternativa scelta, resettalo per renderla visibile
        if let currentSel = selectedOriginStation, !isStationMatch(target.station, currentSel) {
            selectedOriginStation = nil
        }
        
        // Primo scroll immediato e poi animato appena il foglio modale completa la transizione
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            proxy.scrollTo(target.id, anchor: .center)
            
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.4)) {
                proxy.scrollTo(target.id, anchor: .center)
            }
        }
    }
}

// MARK: - Commute Prompt Banner (Home Screen)

struct CommutePromptBannerView: View {
    @ObservedObject var commuteManager = SupporterCommuteManager.shared
    var onConfigure: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles.square.filled.on.square")
                    .font(.title2)
                    .foregroundColor(.pink)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Abitudini di viaggio 💖")
                        .font(.subheadline)
                        .fontWeight(.bold)
                    Text("Configura la tua tratta abituale per ricevere percorsi alternativi in caso di imprevisti o cancellazioni.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            HStack(spacing: 8) {
                Button {
                    onConfigure()
                } label: {
                    Text("Configura ora")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.pink)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button {
                    withAnimation {
                        commuteManager.snoozePromptForTomorrow()
                    }
                } label: {
                    Text("Ricordamelo domani")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button {
                    withAnimation {
                        commuteManager.dismissPromptPermanently()
                    }
                } label: {
                    Image(systemName: "multiply")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.pink.opacity(0.3), lineWidth: 1)
        )
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}


