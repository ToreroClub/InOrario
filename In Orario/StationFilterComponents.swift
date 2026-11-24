import SwiftUI

// MARK: - Toolbar Filter Menu

struct StationFilterToolbarMenu: View {
    let stationName: String
    let allTrains: [Train]
    let favoriteTrainNumbers: Set<String>
    let hasSupport: Bool
    let commuteOrigins: [String]
    let commuteDestinations: [String]
    @ObservedObject var filterController: StationBoardFilterController

    let onSelectCommute: (CommuteTargetFilter) -> Void
    let onRequirePro: () -> Void
    let onOpenCommuteSetup: () -> Void

    private var categoryCounts: [(group: TrainCategoryGroup, count: Int)] {
        var counts: [TrainCategoryGroup: Int] = [:]
        for train in allTrains {
            let group = TrainCategoryGroup.classify(train)
            counts[group, default: 0] += 1
        }
        return TrainCategoryGroup.allCases.compactMap { group in
            let count = counts[group] ?? 0
            if count > 0 || filterController.filterState.selectedCategories.contains(group) {
                return (group, count)
            }
            return nil
        }
    }

    private var suburbanLineCounts: [(line: String, count: Int)] {
        var counts: [String: Int] = [:]
        for train in allTrains {
            if let line = TrainCategoryGroup.suburbanLineCode(for: train) {
                counts[line, default: 0] += 1
            }
        }
        for selected in filterController.filterState.selectedSuburbanLines where counts[selected] == nil {
            counts[selected] = 0
        }
        return counts
            .map { (line: $0.key, count: $0.value) }
            .sorted { a, b in
                let numA = Int(a.line.dropFirst()) ?? 999
                let numB = Int(b.line.dropFirst()) ?? 999
                if numA != numB { return numA < numB }
                return a.line < b.line
            }
    }

    private var hasAnyFavoriteOnBoard: Bool {
        allTrains.contains { train in
            let cleanNum = StationNameMatcher.cleanTrainDigits(train.number)
            return favoriteTrainNumbers.contains(train.number) || favoriteTrainNumbers.contains(cleanNum)
        }
    }

    private var toolbarColor: Color {
        switch filterController.filterState.commuteTarget {
        case .home: return .blue
        case .work: return .green
        case nil: return filterController.filterState.isActive ? .orange : .primary
        }
    }

    var body: some View {
        Menu {
            // SEZIONE 1: Tragitto Abituale (Casa / Lavoro)
            Section("Tragitto abituale") {
                if !hasSupport {
                    Button {
                        Haptics.play(.light)
                        onRequirePro()
                    } label: {
                        Label {
                            Text("Portami a Casa")
                            Text("In Orario Pro")
                        } icon: {
                            Image(systemName: "lock.fill")
                        }
                    }

                    Button {
                        Haptics.play(.light)
                        onRequirePro()
                    } label: {
                        Label {
                            Text("Portami al Lavoro")
                            Text("In Orario Pro")
                        } icon: {
                            Image(systemName: "lock.fill")
                        }
                    }
                } else if commuteOrigins.isEmpty && commuteDestinations.isEmpty {
                    Button {
                        Haptics.play(.light)
                        onOpenCommuteSetup()
                    } label: {
                        Label("Configura Casa e Lavoro…", systemImage: "house.and.flag")
                    }
                } else {
                    if !commuteOrigins.isEmpty {
                        let isHere = commuteOrigins.contains { StationNameMatcher.isSameStation(stationName, $0) }
                        let isSelected = filterController.filterState.commuteTarget == .home
                        let summary = formatCityOrStationSummary(commuteOrigins)
                        Button {
                            Haptics.play(.medium)
                            onSelectCommute(.home)
                        } label: {
                            Label {
                                Text("Portami a Casa")
                                Text(isHere ? "Sei già qui" : summary)
                            } icon: {
                                Image(systemName: isSelected ? "checkmark" : "house.fill")
                            }
                        }
                        .disabled(isHere && !isSelected)
                    }

                    if !commuteDestinations.isEmpty {
                        let isHere = commuteDestinations.contains { StationNameMatcher.isSameStation(stationName, $0) }
                        let isSelected = filterController.filterState.commuteTarget == .work
                        let summary = formatCityOrStationSummary(commuteDestinations)
                        Button {
                            Haptics.play(.medium)
                            onSelectCommute(.work)
                        } label: {
                            Label {
                                Text("Portami al Lavoro")
                                Text(isHere ? "Sei già qui" : summary)
                            } icon: {
                                Image(systemName: isSelected ? "checkmark" : "briefcase.fill")
                            }
                        }
                        .disabled(isHere && !isSelected)
                    }

                    if commuteOrigins.isEmpty || commuteDestinations.isEmpty {
                        Button {
                            Haptics.play(.light)
                            onOpenCommuteSetup()
                        } label: {
                            Label("Configura Casa e Lavoro…", systemImage: "house.and.flag")
                        }
                    }
                }
            }

            // SEZIONE 2: Tipo di treno & Linee Suburbane
            if !categoryCounts.isEmpty || suburbanLineCounts.count >= 2 {
                Section("Tipo di treno") {
                    if !categoryCounts.isEmpty {
                        Menu {
                            ForEach(categoryCounts, id: \.group) { entry in
                                let isSelected = filterController.filterState.selectedCategories.contains(entry.group)
                                Button {
                                    Haptics.play(.light)
                                    if isSelected {
                                        filterController.filterState.selectedCategories.remove(entry.group)
                                    } else {
                                        filterController.filterState.selectedCategories.insert(entry.group)
                                    }
                                } label: {
                                    Label {
                                        Text("\(entry.group.displayTitle) (\(entry.count))")
                                    } icon: {
                                        Image(systemName: isSelected ? "checkmark" : categorySystemImage(entry.group))
                                    }
                                }
                            }
                        } label: {
                            let count = filterController.filterState.selectedCategories.count
                            Label {
                                Text("Tipo di treno")
                                if count > 0 {
                                    Text("\(count) selezionati")
                                }
                            } icon: {
                                Image(systemName: "tram.fill")
                            }
                        }
                    }

                    if suburbanLineCounts.count >= 2 {
                        Menu {
                            ForEach(suburbanLineCounts, id: \.line) { entry in
                                let isSelected = filterController.filterState.selectedSuburbanLines.contains(entry.line)
                                Button {
                                    Haptics.play(.light)
                                    if isSelected {
                                        filterController.filterState.selectedSuburbanLines.remove(entry.line)
                                    } else {
                                        filterController.filterState.selectedSuburbanLines.insert(entry.line)
                                    }
                                } label: {
                                    Label {
                                        Text("\(entry.line) (\(entry.count))")
                                    } icon: {
                                        Image(systemName: isSelected ? "checkmark" : "tram")
                                    }
                                }
                            }
                        } label: {
                            let count = filterController.filterState.selectedSuburbanLines.count
                            Label {
                                Text("Linea Suburbana")
                                if count > 0 {
                                    Text("\(count) selezionate")
                                }
                            } icon: {
                                Image(systemName: "arrow.triangle.branch")
                            }
                        }
                    }
                }
            }

            // SEZIONE 3: Stato e preferenze
            Section("Stato e preferenze") {
                Button {
                    Haptics.play(.light)
                    filterController.filterState.hideCancelled.toggle()
                } label: {
                    Label(
                        "Nascondi cancellati",
                        systemImage: filterController.filterState.hideCancelled ? "checkmark" : "xmark.octagon"
                    )
                }

                Button {
                    Haptics.play(.light)
                    filterController.filterState.onlyWithPlatform.toggle()
                } label: {
                    Label(
                        "Solo con binario",
                        systemImage: filterController.filterState.onlyWithPlatform ? "checkmark" : "signpost.right"
                    )
                }

                Button {
                    Haptics.play(.light)
                    filterController.filterState.onlyOnTime.toggle()
                } label: {
                    Label(
                        "Solo in orario",
                        systemImage: filterController.filterState.onlyOnTime ? "checkmark" : "clock.badge.checkmark"
                    )
                }

                if hasAnyFavoriteOnBoard || filterController.filterState.onlyFavorites {
                    Button {
                        Haptics.play(.light)
                        filterController.filterState.onlyFavorites.toggle()
                    } label: {
                        Label(
                            "Solo preferiti",
                            systemImage: filterController.filterState.onlyFavorites ? "checkmark" : "star.fill"
                        )
                    }
                }
            }

            // SEZIONE 4: Reset
            if filterController.filterState.isActive {
                Section {
                    Button(role: .destructive) {
                        Haptics.play(.medium)
                        filterController.resetAll()
                    } label: {
                        Label("Azzera tutti i filtri", systemImage: "arrow.counterclockwise")
                    }
                }
            }
        } label: {
            if filterController.filterState.isActive {
                HStack(spacing: 4) {
                    if let commute = filterController.filterState.commuteTarget {
                        Image(systemName: commute.iconName)
                            .font(.system(size: 13, weight: .semibold))
                        Text(commute.displayTitle)
                            .font(.system(size: 13, weight: .semibold))
                    } else {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 13, weight: .semibold))
                        Text("\(filterController.filterState.activeFilterCount)")
                            .font(.system(size: 13, weight: .bold).monospacedDigit())
                    }
                }
                .foregroundColor(toolbarColor)
            } else {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
            }
        }
        .accessibilityLabel("Filtra treni")
    }

    private func categorySystemImage(_ group: TrainCategoryGroup) -> String {
        switch group {
        case .highSpeed: return "bolt.fill"
        case .intercity: return "train.side.front.car"
        case .regional: return "tram.fill"
        case .suburban: return "s.circle"
        case .airport: return "airplane"
        case .other: return "ellipsis.circle"
        }
    }
}

// MARK: - Active Filter Chips Bar

struct ActiveStationFiltersBar: View {
    @ObservedObject var filterController: StationBoardFilterController
    let commuteOrigins: [String]
    let commuteDestinations: [String]
    var backgroundColor: Color = Color(.systemGroupedBackground)

    var body: some View {
        if filterController.filterState.isActive {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let target = filterController.filterState.commuteTarget {
                        let pool = target == .home ? commuteOrigins : commuteDestinations
                        let summary = formatCityOrStationSummary(pool)
                        let accent: Color = filterController.isAlreadyAtTargetStation
                            ? .secondary
                            : (target == .home ? .blue : .green)
                        let chipTitle: String = {
                            if filterController.isAlreadyAtTargetStation {
                                return target == .home
                                    ? String(localized: "Sei già a Casa (in pausa)")
                                    : String(localized: "Sei già al Lavoro (in pausa)")
                            }
                            let prefixTitle = target == .home ? String(localized: "Verso Casa") : String(localized: "Verso Lavoro")
                            return summary.isEmpty ? prefixTitle : "\(prefixTitle) • \(summary)"
                        }()

                        Button {
                            Haptics.play(.light)
                            filterController.clearCommuteTarget()
                        } label: {
                            HStack(spacing: 5) {
                                if filterController.isResolvingCommute {
                                    ProgressView()
                                        .controlSize(.mini)
                                        .tint(accent)
                                } else {
                                    Image(systemName: target.iconName)
                                        .font(.caption.bold())
                                }
                                Text(chipTitle)
                                    .font(.caption.bold())
                                    .lineLimit(1)
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .opacity(0.75)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(accent.opacity(0.15))
                            .foregroundColor(accent)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(TrainCategoryGroup.allCases.filter { filterController.filterState.selectedCategories.contains($0) }) { cat in
                        filterChip(title: cat.shortLabel, color: .orange) {
                            filterController.filterState.selectedCategories.remove(cat)
                        }
                    }

                    ForEach(filterController.filterState.selectedSuburbanLines.sorted(), id: \.self) { line in
                        filterChip(title: line, color: .green) {
                            filterController.filterState.selectedSuburbanLines.remove(line)
                        }
                    }

                    if filterController.filterState.hideCancelled {
                        filterChip(title: "No cancellati", color: .orange) {
                            filterController.filterState.hideCancelled = false
                        }
                    }

                    if filterController.filterState.onlyWithPlatform {
                        filterChip(title: "Con binario", color: .orange) {
                            filterController.filterState.onlyWithPlatform = false
                        }
                    }

                    if filterController.filterState.onlyOnTime {
                        filterChip(title: "In orario", color: .green) {
                            filterController.filterState.onlyOnTime = false
                        }
                    }

                    if filterController.filterState.onlyFavorites {
                        filterChip(title: "Preferiti", color: .yellow) {
                            filterController.filterState.onlyFavorites = false
                        }
                    }

                    if filterController.filterState.activeFilterCount >= 2 {
                        Button {
                            Haptics.play(.medium)
                            filterController.resetAll()
                        } label: {
                            Text("Azzera")
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.12))
                                .foregroundColor(.red)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .background(backgroundColor)
        }
    }

    private func filterChip(title: String, color: Color, onRemove: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.light)
            onRemove()
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption.bold())
                    .lineLimit(1)
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .opacity(0.75)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.15))
            .foregroundColor(color == .yellow ? .orange : color)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Filtered Empty / Resolving State View

struct FilteredEmptyBoardView: View {
    @ObservedObject var filterController: StationBoardFilterController
    let onSearchSolutionsWithChanges: () -> Void

    var body: some View {
        if filterController.isResolvingCommute {
            HStack(spacing: 12) {
                ProgressView()
                Text(filterController.filterState.commuteTarget == .work
                     ? "Cerco i treni verso Lavoro…"
                     : "Cerco i treni verso Casa…")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.vertical, 12)
        } else if let target = filterController.filterState.commuteTarget, !filterController.isAlreadyAtTargetStation {
            VStack(spacing: 12) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.title2)
                    .foregroundColor(target == .home ? .blue : .green)

                Text("Nessun treno diretto in partenza verso \(target.displayTitle) al momento.")
                    .font(.subheadline.bold())
                    .multilineTextAlignment(.center)

                Button {
                    Haptics.play(.medium)
                    onSearchSolutionsWithChanges()
                } label: {
                    Label("Cerca soluzioni con cambi", systemImage: "magnifyingglass")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button("Mostra tutti i treni") {
                    Haptics.play(.light)
                    filterController.resetAll()
                }
                .font(.caption.bold())
                .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text("Nessun treno corrisponde ai filtri attivi.")
                    .font(.subheadline.bold())
                    .multilineTextAlignment(.center)
                Button("Rimuovi filtri") {
                    Haptics.play(.light)
                    filterController.resetAll()
                }
                .font(.subheadline.bold())
                .foregroundColor(.orange)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
    }
}
