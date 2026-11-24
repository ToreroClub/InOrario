import SwiftUI

struct CommuteDayTrainEditorTarget: Identifiable {
    let id: Int
}

struct CommuteTimeRangeRow: View {
    let title: String?
    let accentColor: Color
    @Binding var bandString: String

    private var band: CommuteTimeBand {
        CommuteTimeBand.parse(bandString)
    }

    private var startBinding: Binding<Date> {
        Binding<Date>(
            get: { CommuteTimeBand.date(forMinutes: band.startMinutes) },
            set: { newDate in
                let newMins = CommuteTimeBand.minutes(from: newDate)
                bandString = band.updatingStart(to: newMins).formatted
            }
        )
    }

    private var endBinding: Binding<Date> {
        Binding<Date>(
            get: { CommuteTimeBand.date(forMinutes: band.endMinutes) },
            set: { newDate in
                let newMins = CommuteTimeBand.minutes(from: newDate)
                bandString = band.updatingEnd(to: newMins).formatted
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    durationBadge
                }
            }

            HStack(spacing: 6) {
                Text("Dalle")
                    .font(.caption)
                    .foregroundColor(.secondary)

                DatePicker("", selection: startBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(accentColor)
                    .fixedSize(horizontal: true, vertical: false)

                Image(systemName: "arrow.right")
                    .font(.caption2.bold())
                    .foregroundColor(accentColor)

                Text("Alle")
                    .font(.caption)
                    .foregroundColor(.secondary)

                DatePicker("", selection: endBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(accentColor)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 2)

                if title == nil {
                    durationBadge
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var durationBadge: some View {
        Text(band.durationLabel)
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundColor(accentColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(accentColor.opacity(0.14))
            .clipShape(Capsule())
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct CommuteFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0 && currentX + size.width > maxWidth {
                currentX = 0
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }
            totalWidth = max(totalWidth, currentX + size.width)
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        let finalWidth = maxWidth.isFinite ? maxWidth : totalWidth
        return CGSize(width: finalWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > bounds.minX && currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

struct DayTrainsEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let dayIndex: Int
    let dayName: String
    let outboundBand: String
    let returnBand: String
    let outboundOrigins: [String]
    let outboundDestinations: [String]
    let returnOrigins: [String]
    let returnDestinations: [String]
    let initialOutboundTrains: [CommuteHabitTrain]
    let initialReturnTrains: [CommuteHabitTrain]
    let initialOutboundCustomized: Bool
    let initialReturnCustomized: Bool
    let onSave: (
        _ outboundTrains: [CommuteHabitTrain],
        _ returnTrains: [CommuteHabitTrain],
        _ outboundCustomized: Bool,
        _ returnCustomized: Bool
    ) -> Void

    @State private var selectedDirection: Int = 0
    @State private var outboundTrains: [CommuteHabitTrain] = []
    @State private var returnTrains: [CommuteHabitTrain] = []
    @State private var outboundCustomized: Bool = false
    @State private var returnCustomized: Bool = false

    @State private var outboundCandidates: [CommuteHabitTrain] = []
    @State private var returnCandidates: [CommuteHabitTrain] = []
    @State private var hasLoadedOutboundCandidates: Bool = false
    @State private var hasLoadedReturnCandidates: Bool = false
    @State private var isLoadingCandidates: Bool = false

    @State private var searchTrainQuery: String = ""
    @State private var isSearchingNumber: Bool = false
    @State private var numberSearchResults: [CommuteHabitTrain] = []
    @State private var hasSearchedNumber: Bool = false
    @State private var manualFallbackTime: Date = Date()

    private var isReturn: Bool { selectedDirection == 1 }

    private var currentBandString: String {
        isReturn ? returnBand : outboundBand
    }

    private var currentBand: CommuteTimeBand {
        CommuteTimeBand.parse(currentBandString)
    }

    private var currentOrigins: [String] {
        isReturn ? returnOrigins : outboundOrigins
    }

    private var currentDestinations: [String] {
        isReturn ? returnDestinations : outboundDestinations
    }

    private var currentAccent: Color {
        isReturn ? .purple : .blue
    }

    private var activeTrains: [CommuteHabitTrain] {
        let list = isReturn ? returnTrains : outboundTrains
        return CommuteTrainDiscoveryService.deduplicateAndSort(
            list,
            origins: currentOrigins,
            band: currentBand
        )
    }

    private var availableCandidates: [CommuteHabitTrain] {
        let rawCandidates = isReturn ? returnCandidates : outboundCandidates
        let existingNums = Set(activeTrains.map { CommuteTrainDiscoveryService.extractCleanTrainNumber(from: $0.trainNumber) })
        return rawCandidates.filter { cand in
            let num = CommuteTrainDiscoveryService.extractCleanTrainNumber(from: cand.trainNumber)
            return !num.isEmpty && !existingNums.contains(num)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Direzione", selection: $selectedDirection) {
                        Text("Andata (\(compactBand(outboundBand)))").tag(0)
                        Text("Ritorno (\(compactBand(returnBand)))").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 2)
                }

                // SEZIONE 1: TRENI SELEZIONATI
                Section(
                    header: Label(
                        isReturn ? "I tuoi treni (Ritorno)" : "I tuoi treni (Andata)",
                        systemImage: isReturn ? "moon.stars.fill" : "sun.max.fill"
                    ),
                    footer: Text("Puoi rimuovere treni dalla fascia o aggiungerne altri anche fuori fascia. Quando la lista contiene almeno un treno, le notifiche si basano su questi treni.")
                ) {
                    if activeTrains.isEmpty {
                        Text("Nessun treno selezionato. Verrà monitorata l'intera fascia oraria.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(activeTrains) { train in
                            selectedTrainRow(train)
                        }
                        .onDelete(perform: deleteTrainsAtOffsets)
                    }
                }

                // SEZIONE 2: TRENI IN FASCIA E VICINI (±60 MIN)
                Section(header: Text("Treni nella fascia e vicini")) {
                    Button {
                        Task { await loadCandidates(forReturn: isReturn, forceRefresh: true) }
                    } label: {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(currentAccent)
                            Text("Cerca treni in fascia e vicini (±60 min)")
                                .foregroundColor(.primary)
                            Spacer()
                            if isLoadingCandidates {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isLoadingCandidates || currentOrigins.isEmpty || currentDestinations.isEmpty)

                    if !availableCandidates.isEmpty {
                        ForEach(availableCandidates) { cand in
                            candidateTrainRow(cand)
                        }
                    } else if !isLoadingCandidates && (isReturn ? hasLoadedReturnCandidates : hasLoadedOutboundCandidates) {
                        Text("Nessun altro treno disponibile nelle vicinanze della fascia.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button {
                        Task { await restoreBandTrains(forReturn: isReturn) }
                    } label: {
                        Label("Ripristina solo treni in fascia", systemImage: "arrow.counterclockwise")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                    }
                    .disabled(isLoadingCandidates || currentOrigins.isEmpty || currentDestinations.isEmpty)
                }

                // SEZIONE 3: AGGIUNGI PER NUMERO
                Section(
                    header: Text("Aggiungi treno per numero"),
                    footer: Text("Cerca su ViaggiaTreno / Italo direttamente dal tuo iPhone un numero di treno specifico, anche se fuori dalla fascia oraria.")
                ) {
                    HStack(spacing: 8) {
                        TextField("Es. 24627", text: $searchTrainQuery)
                            .keyboardType(.numbersAndPunctuation)
                            .submitLabel(.search)
                            .onSubmit {
                                Task { await runNumberSearch() }
                            }

                        Button {
                            Task { await runNumberSearch() }
                        } label: {
                            if isSearchingNumber {
                                ProgressView()
                            } else {
                                Text("Cerca")
                                    .fontWeight(.semibold)
                            }
                        }
                        .disabled(searchTrainQuery.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || isSearchingNumber)
                    }

                    ForEach(numberSearchResults) { res in
                        searchResultRow(res)
                    }

                    if hasSearchedNumber && numberSearchResults.isEmpty {
                        let digits = CommuteTrainDiscoveryService.extractCleanTrainNumber(from: searchTrainQuery)
                        if !digits.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Nessun riscontro live al momento per il treno \(digits) (potrebbe non circolare oggi o essere fuori orario di esercizio).")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                DatePicker("Orario partenza previsto", selection: $manualFallbackTime, displayedComponents: .hourAndMinute)
                                    .font(.caption)

                                Button {
                                    addManualFallbackTrain(number: digits)
                                } label: {
                                    Label("Aggiungi comunque treno \(digits)", systemImage: "plus.circle.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(currentAccent)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Treni — \(dayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        onSave(outboundTrains, returnTrains, outboundCustomized, returnCustomized)
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                outboundTrains = initialOutboundTrains
                returnTrains = initialReturnTrains
                outboundCustomized = initialOutboundCustomized
                returnCustomized = initialReturnCustomized
                manualFallbackTime = CommuteTimeBand.date(forMinutes: CommuteTimeBand.parse(outboundBand).startMinutes)
                Task { await loadCandidates(forReturn: false, forceRefresh: false) }
            }
            .onChange(of: selectedDirection) { _, newVal in
                let ret = (newVal == 1)
                let b = CommuteTimeBand.parse(ret ? returnBand : outboundBand)
                manualFallbackTime = CommuteTimeBand.date(forMinutes: b.startMinutes)
                numberSearchResults = []
                hasSearchedNumber = false
                if ret && !hasLoadedReturnCandidates {
                    Task { await loadCandidates(forReturn: true, forceRefresh: false) }
                } else if !ret && !hasLoadedOutboundCandidates {
                    Task { await loadCandidates(forReturn: false, forceRefresh: false) }
                }
            }
        }
    }

    private func selectedTrainRow(_ train: CommuteHabitTrain) -> some View {
        let isOutOfBand = !currentBand.contains(timeString: train.departureTime)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(train.departureTime)
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                    if let arr = train.arrivalTime, !arr.isEmpty {
                        Text("→ \(arr)")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    Text("\(train.category) \(train.trainNumber)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(currentAccent.opacity(0.14))
                        .foregroundColor(currentAccent)
                        .cornerRadius(5)

                    if isOutOfBand {
                        Text("Fuori fascia")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.16))
                            .foregroundColor(.orange)
                            .cornerRadius(5)
                    }
                }
                Text("\(train.originStation) → \(train.destinationStation)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                removeTrain(train)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red)
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Rimuovi treno \(train.trainNumber)")
        }
        .padding(.vertical, 2)
    }

    private func candidateTrainRow(_ cand: CommuteHabitTrain) -> some View {
        let isOutOfBand = !currentBand.contains(timeString: cand.departureTime)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(cand.departureTime)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    if let arr = cand.arrivalTime, !arr.isEmpty {
                        Text("→ \(arr)")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    Text("\(cand.category) \(cand.trainNumber)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill))
                        .cornerRadius(5)

                    if isOutOfBand {
                        Text("Fuori fascia")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.16))
                            .foregroundColor(.orange)
                            .cornerRadius(5)
                    }
                }
                Text("\(cand.originStation) → \(cand.destinationStation)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                addCandidateTrain(cand)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Aggiungi treno \(cand.trainNumber)")
        }
        .padding(.vertical, 2)
    }

    private func searchResultRow(_ res: CommuteHabitTrain) -> some View {
        let cleanResNum = CommuteTrainDiscoveryService.extractCleanTrainNumber(from: res.trainNumber)
        let alreadyAdded = activeTrains.contains {
            CommuteTrainDiscoveryService.extractCleanTrainNumber(from: $0.trainNumber) == cleanResNum
        }

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(res.departureTime)
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                    if let arr = res.arrivalTime, !arr.isEmpty {
                        Text("→ \(arr)")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    Text("\(res.category) \(res.trainNumber)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(currentAccent.opacity(0.14))
                        .foregroundColor(currentAccent)
                        .cornerRadius(5)
                }
                Text("\(res.originStation) → \(res.destinationStation)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if alreadyAdded {
                Label("Aggiunto", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold())
                    .foregroundColor(.green)
            } else {
                Button {
                    addCandidateTrain(res, forceManual: true)
                } label: {
                    Label("Aggiungi", systemImage: "plus.circle.fill")
                        .font(.caption.bold())
                        .foregroundColor(.green)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
    }

    private func compactBand(_ band: String) -> String {
        CommuteTimeBand.parse(band).compactFormatted
    }

    private func deleteTrainsAtOffsets(_ offsets: IndexSet) {
        let sorted = activeTrains
        let toRemove = offsets.map { sorted[$0] }
        for tr in toRemove {
            removeTrain(tr)
        }
    }

    private func removeTrain(_ train: CommuteHabitTrain) {
        Haptics.play(.light)
        let clean = CommuteTrainDiscoveryService.extractCleanTrainNumber(from: train.trainNumber)
        if isReturn {
            returnTrains.removeAll {
                $0.id == train.id || CommuteTrainDiscoveryService.extractCleanTrainNumber(from: $0.trainNumber) == clean
            }
            returnCustomized = true
        } else {
            outboundTrains.removeAll {
                $0.id == train.id || CommuteTrainDiscoveryService.extractCleanTrainNumber(from: $0.trainNumber) == clean
            }
            outboundCustomized = true
        }
    }

    private func addCandidateTrain(_ cand: CommuteHabitTrain, forceManual: Bool = false) {
        Haptics.play(.light)
        let isOutOfBand = !currentBand.contains(timeString: cand.departureTime)
        var item = cand
        item.isManuallyAdded = forceManual || isOutOfBand

        let clean = CommuteTrainDiscoveryService.extractCleanTrainNumber(from: item.trainNumber)
        if isReturn {
            if !returnTrains.contains(where: { CommuteTrainDiscoveryService.extractCleanTrainNumber(from: $0.trainNumber) == clean }) {
                returnTrains.append(item)
                returnTrains = CommuteTrainDiscoveryService.deduplicateAndSort(returnTrains, origins: currentOrigins, band: currentBand)
            }
            returnCustomized = true
        } else {
            if !outboundTrains.contains(where: { CommuteTrainDiscoveryService.extractCleanTrainNumber(from: $0.trainNumber) == clean }) {
                outboundTrains.append(item)
                outboundTrains = CommuteTrainDiscoveryService.deduplicateAndSort(outboundTrains, origins: currentOrigins, band: currentBand)
            }
            outboundCustomized = true
        }
    }

    private func addManualFallbackTrain(number: String) {
        let hhmm = SharedFormatters.time.string(from: manualFallbackTime)
        let item = CommuteHabitTrain(
            trainNumber: number,
            category: isItaloTrain(number: number) ? "Italo" : "Treno",
            originStation: currentOrigins.first ?? "Partenza",
            destinationStation: currentDestinations.first ?? "Arrivo",
            departureTime: hhmm,
            arrivalTime: nil,
            isManuallyAdded: true
        )
        addCandidateTrain(item, forceManual: true)
        searchTrainQuery = ""
        numberSearchResults = []
        hasSearchedNumber = false
    }

    private func loadCandidates(forReturn: Bool, forceRefresh: Bool) async {
        let origs = forReturn ? returnOrigins : outboundOrigins
        let dests = forReturn ? returnDestinations : outboundDestinations
        let bandStr = forReturn ? returnBand : outboundBand
        guard !origs.isEmpty && !dests.isEmpty else { return }

        isLoadingCandidates = true
        defer { isLoadingCandidates = false }

        let found = await CommuteTrainDiscoveryService.shared.discoverTrains(
            weekday: dayIndex,
            bandString: bandStr,
            origins: origs,
            destinations: dests,
            extraMarginBefore: 60,
            extraMarginAfter: 60,
            forceRefresh: forceRefresh
        )

        if forReturn {
            returnCandidates = found
            hasLoadedReturnCandidates = true
        } else {
            outboundCandidates = found
            hasLoadedOutboundCandidates = true
        }
    }

    private func restoreBandTrains(forReturn: Bool) async {
        let origs = forReturn ? returnOrigins : outboundOrigins
        let dests = forReturn ? returnDestinations : outboundDestinations
        let bandStr = forReturn ? returnBand : outboundBand
        guard !origs.isEmpty && !dests.isEmpty else { return }

        isLoadingCandidates = true
        defer { isLoadingCandidates = false }

        let found = await CommuteTrainDiscoveryService.shared.discoverTrains(
            weekday: dayIndex,
            bandString: bandStr,
            origins: origs,
            destinations: dests,
            extraMarginBefore: 0,
            extraMarginAfter: 0,
            forceRefresh: true
        )
        Haptics.play(.light)
        if forReturn {
            returnTrains = found
            returnCustomized = false
        } else {
            outboundTrains = found
            outboundCustomized = false
        }
    }

    private func runNumberSearch() async {
        let q = searchTrainQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }

        isSearchingNumber = true
        hasSearchedNumber = false
        defer {
            isSearchingNumber = false
            hasSearchedNumber = true
        }

        numberSearchResults = await CommuteTrainDiscoveryService.shared.lookupTrainByNumber(
            q,
            preferredOrigins: currentOrigins,
            preferredDestinations: currentDestinations
        )
    }
}
