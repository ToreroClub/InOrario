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
    @State private var expandedDays: Set<Int> = []
    @State private var proactiveAlerts: Bool = true
    
    // Station Pickers
    @State private var showOriginPicker: Bool = false
    @State private var showDestPicker: Bool = false
    @State private var tempOriginName: String = ""
    @State private var tempOriginID: String = ""
    @State private var tempDestName: String = ""
    @State private var tempDestID: String = ""
    
    // Simulation & Discovery
    @State private var simulationTripType: Bool = false // false = andata, true = ritorno
    @State private var isSaving: Bool = false
    @State private var showPlanBSheet: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    @State private var editingTrainsDayTarget: CommuteDayTrainEditorTarget? = nil
    @State private var discoveringKeys: Set<String> = []
    @State private var discoveryTask: Task<Void, Never>? = nil
    @State private var perDayDiscoveryTasks: [String: Task<Void, Never>] = [:]
    
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
                Text("Il server monitora la tua tratta abituale in caso di cancellazioni o gravi ritardi e riceverai un'alternativa. Personalizza le tue stazioni di partenza, arrivo e viceversa e gli orari per ogni singolo giorno.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 2)
            }
            
            // STAZIONI DI PARTENZA
            Section(
                header: Label("Stazioni di partenza (Casa)", systemImage: "house.fill"),
                footer: Text("Usate anche per il filtro \"Portami a Casa\" nei tabelloni stazione.")
            ) {
                if origins.isEmpty {
                    Text("Nessuna stazione di partenza impostata")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(origins, id: \.self) { st in
                        HStack {
                            Image(systemName: "house.fill")
                                .foregroundColor(.blue)
                            Text(st)
                                .font(.body)
                            Spacer()
                            Button {
                                origins.removeAll { $0 == st }
                                pruneStationFromExclusions(st)
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
            Section(
                header: Label("Stazioni di arrivo (Lavoro)", systemImage: "briefcase.fill"),
                footer: Text("Usate anche per il filtro \"Portami al Lavoro\" nei tabelloni stazione.")
            ) {
                if destinations.isEmpty {
                    Text("Nessuna stazione di arrivo impostata")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(destinations, id: \.self) { st in
                        HStack {
                            Image(systemName: "briefcase.fill")
                                .foregroundColor(.green)
                            Text(st)
                                .font(.body)
                            Spacer()
                            Button {
                                destinations.removeAll { $0 == st }
                                pruneStationFromExclusions(st)
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
                    CommuteTimeRangeRow(
                        title: "Andata",
                        accentColor: .blue,
                        bandString: $defaultOutboundBand
                    )
                    
                    CommuteTimeRangeRow(
                        title: "Ritorno",
                        accentColor: .purple,
                        bandString: $defaultReturnBand
                    )
                    
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
                        let sched = daySchedules[dayIndex] ?? DayCommuteSchedule(
                            isEnabled: selectedWeekdays.contains(dayIndex),
                            outboundBand: defaultOutboundBand,
                            returnBand: defaultReturnBand
                        )
                        let isEnabled = sched.isEnabled
                        let outbound = sched.outboundBand
                        let ret = sched.returnBand
                        let isExpanded = expandedDays.contains(dayIndex)

                        HStack(alignment: .center, spacing: 8) {
                            Button {
                                if isEnabled {
                                    let enabledCount = weekdayNames.filter { daySchedules[$0.0]?.isEnabled ?? selectedWeekdays.contains($0.0) }.count
                                    if enabledCount <= 1 {
                                        Haptics.notify(.warning)
                                        return
                                    }
                                }
                                Haptics.play(.light)
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    var cur = sched
                                    cur.isEnabled.toggle()
                                    daySchedules[dayIndex] = cur
                                    if !cur.isEnabled {
                                        expandedDays.remove(dayIndex)
                                    }
                                }
                                if !isEnabled {
                                    scheduleDiscoverForDayIfEmpty(dayIndex)
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 13, weight: .bold))
                                    Text(fullName)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isEnabled ? Color.blue.opacity(0.15) : Color(.tertiarySystemFill))
                                .foregroundColor(isEnabled ? .blue : .secondary)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            Spacer(minLength: 6)

                            if !isEnabled {
                                Text("Nessun viaggio")
                                    .font(.footnote)
                                    .foregroundColor(.secondary.opacity(0.6))
                                    .strikethrough(true, color: .secondary.opacity(0.5))
                                    .lineLimit(1)
                                    .padding(.trailing, 4)
                            } else {
                                Button {
                                    Haptics.play(.light)
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        if isExpanded {
                                            expandedDays.remove(dayIndex)
                                        } else {
                                            expandedDays.insert(dayIndex)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text("\(compactBand(outbound))  •  \(compactBand(ret))")
                                                .font(.caption.weight(.semibold))
                                                .monospacedDigit()
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.8)
                                                .foregroundColor(.primary)
                                            if sched.hasCustomStationExclusions {
                                                Text("Stazioni personalizzate")
                                                    .font(.caption2.bold())
                                                    .foregroundColor(.orange)
                                            } else {
                                                Text("Tutte le stazioni")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.secondary)
                                            .frame(width: 18, height: 18)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                        .id("day_hdr_\(dayIndex)")

                        if isEnabled && isExpanded {
                            dayDetailCard(
                                dayIndex: dayIndex,
                                sched: sched,
                                outbound: outbound,
                                ret: ret
                            )
                            .listRowSeparator(.hidden, edges: .top)
                            .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 10, trailing: 16))
                            .id("day_det_\(dayIndex)")
                        }
                    }
                }
            }

            // TABELLA TRENI PER GIORNO (CALCOLATA ON-DEVICE SU IPHONE)
            trainsTableSection
            
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
        .onDisappear {
            discoveryTask?.cancel()
            for task in perDayDiscoveryTasks.values {
                task.cancel()
            }
            perDayDiscoveryTasks.removeAll()
            if applyLocalSettingsToManager() {
                Task {
                    await commuteManager.syncRoutineWithServer()
                }
            }
        }
        .onChange(of: origins) { _, _ in
            guard !isHydratingInitialState else { return }
            scheduleDiscoverAllActive(forceRefresh: false)
        }
        .onChange(of: destinations) { _, _ in
            guard !isHydratingInitialState else { return }
            scheduleDiscoverAllActive(forceRefresh: false)
        }
        .onChange(of: defaultOutboundBand) { _, newBand in
            guard !isHydratingInitialState, !customizePerDay else { return }
            for (d, _, _) in weekdayNames {
                var cur = daySchedules[d] ?? DayCommuteSchedule(isEnabled: selectedWeekdays.contains(d), outboundBand: newBand, returnBand: defaultReturnBand)
                cur.outboundBand = newBand
                daySchedules[d] = cur
            }
            scheduleDiscoverGlobalDirection(isReturn: false)
        }
        .onChange(of: defaultReturnBand) { _, newBand in
            guard !isHydratingInitialState, !customizePerDay else { return }
            for (d, _, _) in weekdayNames {
                var cur = daySchedules[d] ?? DayCommuteSchedule(isEnabled: selectedWeekdays.contains(d), outboundBand: defaultOutboundBand, returnBand: newBand)
                cur.returnBand = newBand
                daySchedules[d] = cur
            }
            scheduleDiscoverGlobalDirection(isReturn: true)
        }
        .onChange(of: selectedWeekdays) { _, newDays in
            guard !isHydratingInitialState, !customizePerDay else { return }
            for (d, _, _) in weekdayNames {
                var cur = daySchedules[d] ?? DayCommuteSchedule(isEnabled: newDays.contains(d), outboundBand: defaultOutboundBand, returnBand: defaultReturnBand)
                cur.isEnabled = newDays.contains(d)
                daySchedules[d] = cur
            }
            scheduleDiscoverMissingTrains()
        }
        .onChange(of: customizePerDay) { _, _ in
            guard !isHydratingInitialState else { return }
            scheduleDiscoverMissingTrains()
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
        // Sheet Modifica Treni Giorno (Matita)
        .sheet(item: $editingTrainsDayTarget) { target in
            let dIdx = target.id
            let dayName = weekdayNames.first(where: { $0.0 == dIdx })?.2 ?? "Giorno"
            let sched = daySchedules[dIdx] ?? DayCommuteSchedule(
                isEnabled: selectedWeekdays.contains(dIdx),
                outboundBand: defaultOutboundBand,
                returnBand: defaultReturnBand
            )
            let outBand = customizePerDay ? sched.outboundBand : defaultOutboundBand
            let retBand = customizePerDay ? sched.returnBand : defaultReturnBand
            let outSt = effectiveStationsForUI(dayIndex: dIdx, isReturn: false)
            let retSt = effectiveStationsForUI(dayIndex: dIdx, isReturn: true)

            DayTrainsEditorSheet(
                dayIndex: dIdx,
                dayName: dayName,
                outboundBand: outBand,
                returnBand: retBand,
                outboundOrigins: outSt.origins,
                outboundDestinations: outSt.destinations,
                returnOrigins: retSt.origins,
                returnDestinations: retSt.destinations,
                initialOutboundTrains: sched.outboundTrains,
                initialReturnTrains: sched.returnTrains,
                initialOutboundCustomized: sched.outboundTrainsCustomized,
                initialReturnCustomized: sched.returnTrainsCustomized
            ) { newOutbound, newReturn, outCustom, retCustom in
                var updated = daySchedules[dIdx] ?? DayCommuteSchedule(
                    isEnabled: isDayActiveForUI(dIdx),
                    outboundBand: outBand,
                    returnBand: retBand
                )
                updated.outboundTrains = newOutbound
                updated.returnTrains = newReturn
                updated.outboundTrainsCustomized = outCustom
                updated.returnTrainsCustomized = retCustom
                daySchedules[dIdx] = updated
            }
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
    
    @State private var hasLoadedInitialState: Bool = false
    @State private var isHydratingInitialState: Bool = true

    private func loadInitialState() {
        guard !hasLoadedInitialState else { return }
        hasLoadedInitialState = true
        isHydratingInitialState = true

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
        } else {
            for (dayIndex, _, _) in weekdayNames where daySchedules[dayIndex] == nil {
                daySchedules[dayIndex] = DayCommuteSchedule(
                    isEnabled: selectedWeekdays.contains(dayIndex),
                    outboundBand: defaultOutboundBand,
                    returnBand: defaultReturnBand
                )
            }
        }

        DispatchQueue.main.async {
            isHydratingInitialState = false
            scheduleDiscoverMissingTrains()
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
    
    private func applyLocalSettingsToManager() -> Bool {
        guard !origins.isEmpty && !destinations.isEmpty else { return false }
        let changed =
            commuteManager.origins != origins ||
            commuteManager.destinations != destinations ||
            commuteManager.defaultOutboundBand != defaultOutboundBand ||
            commuteManager.defaultReturnBand != defaultReturnBand ||
            commuteManager.activeWeekdays != selectedWeekdays ||
            commuteManager.customizePerDay != customizePerDay ||
            commuteManager.daySchedules != daySchedules ||
            commuteManager.proactiveAlertsEnabled != proactiveAlerts
        guard changed else { return false }

        commuteManager.origins = origins
        commuteManager.destinations = destinations
        commuteManager.defaultOutboundBand = defaultOutboundBand
        commuteManager.defaultReturnBand = defaultReturnBand
        commuteManager.activeWeekdays = selectedWeekdays
        commuteManager.customizePerDay = customizePerDay
        commuteManager.daySchedules = daySchedules
        commuteManager.proactiveAlertsEnabled = proactiveAlerts
        return true
    }

    private func saveSettings() async {
        isSaving = true
        defer { isSaving = false }

        _ = applyLocalSettingsToManager()
        await commuteManager.syncRoutineWithServer()
    }

    private func pruneStationFromExclusions(_ station: String) {
        for dayIndex in daySchedules.keys {
            var cur = daySchedules[dayIndex] ?? DayCommuteSchedule()
            cur.excludedOutboundOrigins.removeAll { $0 == station }
            cur.excludedOutboundDestinations.removeAll { $0 == station }
            cur.excludedReturnOrigins.removeAll { $0 == station }
            cur.excludedReturnDestinations.removeAll { $0 == station }
            daySchedules[dayIndex] = cur
        }
    }

    private func toggleStationExclusion(
        dayIndex: Int,
        station: String,
        pool: [String],
        keyPath: WritableKeyPath<DayCommuteSchedule, [String]>,
        isReturnDirection: Bool
    ) {
        var cur = daySchedules[dayIndex] ?? DayCommuteSchedule(
            isEnabled: selectedWeekdays.contains(dayIndex),
            outboundBand: defaultOutboundBand,
            returnBand: defaultReturnBand
        )
        var excl = cur[keyPath: keyPath]
        if let idx = excl.firstIndex(of: station) {
            excl.remove(at: idx)
            Haptics.play(.light)
        } else {
            let activeCount = pool.filter { !excl.contains($0) }.count
            if activeCount <= 1 {
                Haptics.notify(.warning)
                return
            }
            excl.append(station)
            Haptics.play(.light)
        }
        cur[keyPath: keyPath] = excl
        daySchedules[dayIndex] = cur
        scheduleDiscoverSingleDayDirection(dayIndex: dayIndex, isReturn: isReturnDirection)
    }

    private func compactBand(_ band: String) -> String {
        CommuteTimeBand.parse(band).compactFormatted
    }

    private func isDayActiveForUI(_ dayIndex: Int) -> Bool {
        if customizePerDay {
            return daySchedules[dayIndex]?.isEnabled ?? selectedWeekdays.contains(dayIndex)
        }
        return selectedWeekdays.contains(dayIndex)
    }

    private var activeDaysForDisplay: [(Int, String, String)] {
        weekdayNames.filter { isDayActiveForUI($0.0) }
    }

    private func effectiveStationsForUI(dayIndex: Int, isReturn: Bool) -> (origins: [String], destinations: [String]) {
        if customizePerDay {
            return SupporterCommuteManager.resolveEffectiveStations(
                baseOrigins: origins,
                baseDestinations: destinations,
                schedule: daySchedules[dayIndex],
                isReturn: isReturn
            )
        }
        return isReturn ? (destinations, origins) : (origins, destinations)
    }

    private var trainsTableSection: some View {
        Section(
            header: HStack {
                Text("Treni")
                Spacer()
                if !origins.isEmpty && !destinations.isEmpty {
                    Button {
                        Haptics.play(.light)
                        scheduleDiscoverAllActive(forceRefresh: true)
                    } label: {
                        if !discoveringKeys.isEmpty {
                            ProgressView()
                                .scaleEffect(0.75)
                        } else {
                            Label("Aggiorna", systemImage: "arrow.clockwise")
                                .font(.caption.weight(.semibold))
                                .textCase(nil)
                        }
                    }
                    .disabled(!discoveringKeys.isEmpty)
                }
            },
            footer: Text("I treni vengono cercati direttamente dal tuo iPhone in base alle fasce orarie sopra. Tocca la matita per modificare i treni di un giorno: le notifiche monitoreranno questi treni evitando falsi avvisi per altre corse.")
        ) {
            if origins.isEmpty || destinations.isEmpty {
                Text("Imposta le stazioni di partenza e arrivo per trovare automaticamente i tuoi treni.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else if activeDaysForDisplay.isEmpty {
                Text("Seleziona almeno un giorno di viaggio.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(activeDaysForDisplay, id: \.0) { dayIndex, _, fullName in
                    let sched = daySchedules[dayIndex] ?? DayCommuteSchedule(
                        isEnabled: true,
                        outboundBand: defaultOutboundBand,
                        returnBand: defaultReturnBand
                    )
                    let outBand = customizePerDay ? sched.outboundBand : defaultOutboundBand
                    let retBand = customizePerDay ? sched.returnBand : defaultReturnBand
                    let outOrigins = effectiveStationsForUI(dayIndex: dayIndex, isReturn: false).origins
                    let retOrigins = effectiveStationsForUI(dayIndex: dayIndex, isReturn: true).origins

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(fullName)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button {
                                Haptics.play(.light)
                                editingTrainsDayTarget = CommuteDayTrainEditorTarget(id: dayIndex)
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.caption.bold())
                                    .foregroundColor(.blue)
                                    .frame(width: 28, height: 28)
                                    .background(Color.blue.opacity(0.12))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Modifica treni di \(fullName)")
                        }

                        dayDirectionTrainsBlock(
                            title: "Andata",
                            iconName: "sun.max.fill",
                            accentColor: .blue,
                            band: outBand,
                            trains: sched.outboundTrains,
                            isDiscovering: discoveringKeys.contains("\(dayIndex)_out"),
                            showOriginPrefix: outOrigins.count > 1
                        )

                        Divider()

                        dayDirectionTrainsBlock(
                            title: "Ritorno",
                            iconName: "moon.stars.fill",
                            accentColor: .purple,
                            band: retBand,
                            trains: sched.returnTrains,
                            isDiscovering: discoveringKeys.contains("\(dayIndex)_ret"),
                            showOriginPrefix: retOrigins.count > 1
                        )
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func dayDirectionTrainsBlock(
        title: String,
        iconName: String,
        accentColor: Color,
        band: String,
        trains: [CommuteHabitTrain],
        isDiscovering: Bool,
        showOriginPrefix: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.caption)
                    .foregroundColor(accentColor)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(accentColor)
                Text(compactBand(band))
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                Spacer()
            }

            if isDiscovering {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.75)
                    Text("Ricerca treni su ViaggiaTreno...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if trains.isEmpty {
                Text("Nessun treno trovato in fascia")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                CommuteFlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(trains) { train in
                        habitTrainChip(train, accentColor: accentColor, showOriginPrefix: showOriginPrefix)
                    }
                }
            }
        }
    }

    private func habitTrainChip(
        _ train: CommuteHabitTrain,
        accentColor: Color,
        showOriginPrefix: Bool
    ) -> some View {
        let chipTint: Color = train.isManuallyAdded ? .orange : accentColor
        return HStack(spacing: 4) {
            Text(train.departureTime)
                .font(.caption2.bold())
                .monospacedDigit()
                .foregroundColor(.primary)
            Text("\(train.category) \(train.trainNumber)")
                .font(.caption2.weight(.semibold))
                .foregroundColor(chipTint)
            if showOriginPrefix && !train.originStation.isEmpty {
                Text("(\(Train.cleanStationName(train.originStation)))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(chipTint.opacity(0.11))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(chipTint.opacity(train.isManuallyAdded ? 0.45 : 0.2), lineWidth: 1)
        )
        .cornerRadius(7)
    }

    // MARK: - On-Device Discovery Orchestration

    private func scheduleDiscoverMissingTrains() {
        guard !origins.isEmpty && !destinations.isEmpty else { return }
        discoveryTask?.cancel()
        discoveryTask = Task {
            let active = activeDaysForDisplay
            var workItems: [(Int, Bool)] = []
            for (dayIndex, _, _) in active {
                let sched = daySchedules[dayIndex] ?? DayCommuteSchedule()
                if sched.outboundTrains.isEmpty && !sched.outboundTrainsCustomized {
                    workItems.append((dayIndex, false))
                }
                if sched.returnTrains.isEmpty && !sched.returnTrainsCustomized {
                    workItems.append((dayIndex, true))
                }
            }
            for (dayIndex, isRet) in workItems {
                guard !Task.isCancelled else { return }
                await discoverDirection(dayIndex: dayIndex, isReturn: isRet, mergeManual: true, forceRefresh: false)
            }
        }
    }

    private func scheduleDiscoverForDayIfEmpty(_ dayIndex: Int) {
        guard !origins.isEmpty && !destinations.isEmpty else { return }
        let sched = daySchedules[dayIndex] ?? DayCommuteSchedule()
        let needOut = sched.outboundTrains.isEmpty && !sched.outboundTrainsCustomized
        let needRet = sched.returnTrains.isEmpty && !sched.returnTrainsCustomized
        guard needOut || needRet else { return }
        Task {
            if needOut {
                await discoverDirection(dayIndex: dayIndex, isReturn: false, mergeManual: true, forceRefresh: false)
            }
            if needRet {
                await discoverDirection(dayIndex: dayIndex, isReturn: true, mergeManual: true, forceRefresh: false)
            }
        }
    }

    private func scheduleDiscoverAllActive(forceRefresh: Bool) {
        discoveryTask?.cancel()
        guard !origins.isEmpty && !destinations.isEmpty else { return }
        discoveryTask = Task {
            if !forceRefresh {
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard !Task.isCancelled else { return }
            } else {
                await CommuteTrainDiscoveryService.shared.clearCache()
            }
            for (dayIndex, _, _) in activeDaysForDisplay {
                guard !Task.isCancelled else { return }
                await discoverDirection(dayIndex: dayIndex, isReturn: false, mergeManual: true, forceRefresh: forceRefresh)
                guard !Task.isCancelled else { return }
                await discoverDirection(dayIndex: dayIndex, isReturn: true, mergeManual: true, forceRefresh: forceRefresh)
            }
        }
    }

    private func scheduleDiscoverGlobalDirection(isReturn: Bool) {
        discoveryTask?.cancel()
        guard !origins.isEmpty && !destinations.isEmpty else { return }
        discoveryTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            for (dayIndex, _, _) in activeDaysForDisplay {
                guard !Task.isCancelled else { return }
                await discoverDirection(dayIndex: dayIndex, isReturn: isReturn, mergeManual: true, forceRefresh: false)
            }
        }
    }

    private func scheduleDiscoverSingleDayDirection(dayIndex: Int, isReturn: Bool) {
        guard !origins.isEmpty && !destinations.isEmpty else { return }
        let taskKey = "\(dayIndex)_\(isReturn ? "ret" : "out")"
        perDayDiscoveryTasks[taskKey]?.cancel()
        perDayDiscoveryTasks[taskKey] = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await discoverDirection(dayIndex: dayIndex, isReturn: isReturn, mergeManual: true, forceRefresh: false)
        }
    }

    private func discoverDirection(
        dayIndex: Int,
        isReturn: Bool,
        mergeManual: Bool,
        forceRefresh: Bool
    ) async {
        guard !origins.isEmpty && !destinations.isEmpty else { return }
        let key = "\(dayIndex)_\(isReturn ? "ret" : "out")"
        discoveringKeys.insert(key)
        defer { discoveringKeys.remove(key) }

        let currentSched = daySchedules[dayIndex] ?? DayCommuteSchedule(
            isEnabled: isDayActiveForUI(dayIndex),
            outboundBand: defaultOutboundBand,
            returnBand: defaultReturnBand
        )
        let bandStr = customizePerDay
            ? (isReturn ? currentSched.returnBand : currentSched.outboundBand)
            : (isReturn ? defaultReturnBand : defaultOutboundBand)
        let eff = effectiveStationsForUI(dayIndex: dayIndex, isReturn: isReturn)

        let discovered = await CommuteTrainDiscoveryService.shared.discoverTrains(
            weekday: dayIndex,
            bandString: bandStr,
            origins: eff.origins,
            destinations: eff.destinations,
            extraMarginBefore: 0,
            extraMarginAfter: 0,
            forceRefresh: forceRefresh
        )

        guard !Task.isCancelled, !origins.isEmpty && !destinations.isEmpty else { return }

        var latestSched = daySchedules[dayIndex] ?? currentSched
        let band = CommuteTimeBand.parse(bandStr)
        if isReturn {
            latestSched.returnTrains = mergeManual
                ? CommuteTrainDiscoveryService.mergeDiscoveredWithExisting(
                    discovered: discovered,
                    existing: latestSched.returnTrains,
                    band: band,
                    origins: eff.origins
                )
                : discovered
        } else {
            latestSched.outboundTrains = mergeManual
                ? CommuteTrainDiscoveryService.mergeDiscoveredWithExisting(
                    discovered: discovered,
                    existing: latestSched.outboundTrains,
                    band: band,
                    origins: eff.origins
                )
                : discovered
        }
        daySchedules[dayIndex] = latestSched
    }

    private func directionArrowBadge(color: Color) -> some View {
        HStack {
            Spacer()
            Image(systemName: "arrow.down")
                .font(.caption.bold())
                .foregroundColor(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.14))
                .clipShape(Circle())
            Spacer()
        }
        .padding(.vertical, 1)
    }

    private func dayDetailCard(
        dayIndex: Int,
        sched: DayCommuteSchedule,
        outbound: String,
        ret: String
    ) -> some View {
        let outboundBandBinding = Binding<String>(
            get: { daySchedules[dayIndex]?.outboundBand ?? outbound },
            set: { newBand in
                var cur = daySchedules[dayIndex] ?? sched
                cur.outboundBand = newBand
                daySchedules[dayIndex] = cur
                scheduleDiscoverSingleDayDirection(dayIndex: dayIndex, isReturn: false)
            }
        )
        let returnBandBinding = Binding<String>(
            get: { daySchedules[dayIndex]?.returnBand ?? ret },
            set: { newBand in
                var cur = daySchedules[dayIndex] ?? sched
                cur.returnBand = newBand
                daySchedules[dayIndex] = cur
                scheduleDiscoverSingleDayDirection(dayIndex: dayIndex, isReturn: true)
            }
        )

        return VStack(alignment: .leading, spacing: 12) {
            // Blocco Andata
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sun.max.fill")
                    Text("Andata")
                }
                .font(.subheadline.bold())
                .foregroundColor(.blue)

                CommuteTimeRangeRow(
                    title: nil,
                    accentColor: .blue,
                    bandString: outboundBandBinding
                )

                if !origins.isEmpty {
                    stationSelectorList(
                        accentColor: .blue,
                        pool: origins,
                        excluded: sched.excludedOutboundOrigins
                    ) { st in
                        toggleStationExclusion(
                            dayIndex: dayIndex,
                            station: st,
                            pool: origins,
                            keyPath: \.excludedOutboundOrigins,
                            isReturnDirection: false
                        )
                    }
                }

                if !origins.isEmpty && !destinations.isEmpty {
                    directionArrowBadge(color: .blue)
                }

                if !destinations.isEmpty {
                    stationSelectorList(
                        accentColor: .blue,
                        pool: destinations,
                        excluded: sched.excludedOutboundDestinations
                    ) { st in
                        toggleStationExclusion(
                            dayIndex: dayIndex,
                            station: st,
                            pool: destinations,
                            keyPath: \.excludedOutboundDestinations,
                            isReturnDirection: false
                        )
                    }
                }
            }

            Divider()

            // Blocco Ritorno
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "moon.stars.fill")
                    Text("Ritorno")
                }
                .font(.subheadline.bold())
                .foregroundColor(.purple)

                CommuteTimeRangeRow(
                    title: nil,
                    accentColor: .purple,
                    bandString: returnBandBinding
                )

                if !destinations.isEmpty {
                    stationSelectorList(
                        accentColor: .purple,
                        pool: destinations,
                        excluded: sched.excludedReturnOrigins
                    ) { st in
                        toggleStationExclusion(
                            dayIndex: dayIndex,
                            station: st,
                            pool: destinations,
                            keyPath: \.excludedReturnOrigins,
                            isReturnDirection: true
                        )
                    }
                }

                if !origins.isEmpty && !destinations.isEmpty {
                    directionArrowBadge(color: .purple)
                }

                if !origins.isEmpty {
                    stationSelectorList(
                        accentColor: .purple,
                        pool: origins,
                        excluded: sched.excludedReturnDestinations
                    ) { st in
                        toggleStationExclusion(
                            dayIndex: dayIndex,
                            station: st,
                            pool: origins,
                            keyPath: \.excludedReturnDestinations,
                            isReturnDirection: true
                        )
                    }
                }
            }

            if sched.hasCustomStationExclusions {
                Button {
                    Haptics.play(.light)
                    var cur = sched
                    cur.excludedOutboundOrigins = []
                    cur.excludedOutboundDestinations = []
                    cur.excludedReturnOrigins = []
                    cur.excludedReturnDestinations = []
                    daySchedules[dayIndex] = cur
                    scheduleDiscoverSingleDayDirection(dayIndex: dayIndex, isReturn: false)
                    scheduleDiscoverSingleDayDirection(dayIndex: dayIndex, isReturn: true)
                } label: {
                    Label("Ripristina tutte le stazioni", systemImage: "arrow.counterclockwise")
                        .font(.caption.bold())
                        .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemFill).opacity(0.6))
        .cornerRadius(12)
    }

    private func stationSelectorList(
        accentColor: Color,
        pool: [String],
        excluded: [String],
        onToggle: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(pool, id: \.self) { st in
                let isIncluded = !excluded.contains(st)
                Button {
                    onToggle(st)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14))
                            .foregroundColor(isIncluded ? accentColor : .secondary)
                        Text(st)
                            .font(.caption)
                            .foregroundColor(isIncluded ? .primary : .secondary)
                            .strikethrough(!isIncluded, color: .secondary.opacity(0.6))
                        Spacer()
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(isIncluded ? Color(.secondarySystemGroupedBackground) : Color.clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
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
                if let incType = currentPlan.incident_type,
                   incType.hasPrefix("summary_") || incType == "cancelled" || incType == "delay" {
                    let bannerStyle: (icon: String, color: Color) = {
                        switch incType {
                        case "summary_ok":
                            return ("checkmark.seal.fill", .green)
                        case "summary_warning":
                            return ("exclamationmark.triangle.fill", .orange)
                        default:
                            return ("xmark.octagon.fill", .red)
                        }
                    }()
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: bannerStyle.icon)
                            .font(.title3)
                            .foregroundColor(bannerStyle.color)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(currentPlan.title)
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            Text(currentPlan.body)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(bannerStyle.color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(bannerStyle.color.opacity(0.35), lineWidth: 1)
                    )
                    .padding(.horizontal)
                }

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
        .onDisappear {
            if (currentPlan.incident_type == "summary_ok" || currentPlan.incident_type == "simulation"),
               commuteManager.chosenAlternativeId == nil {
                commuteManager.activePlanB = nil
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(currentPlan.incident_type?.hasPrefix("summary_") == true ? "Riepilogo Tratta" : "Alternative di viaggio")
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


