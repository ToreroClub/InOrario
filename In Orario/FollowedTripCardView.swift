import SwiftUI

struct FollowedTripCardView: View {
    let trip: FollowedTrip

    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var cache: MetroCache
    @EnvironmentObject var usageTracker: UsageTracker

    @ObservedObject private var commuteManager = SupporterCommuteManager.shared

    @State private var results: [String: StopsResult] = [:]
    @State private var selectedTrain: Train? = nil
    @State private var showTripDetails: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView

            Divider()

            VStack(spacing: 8) {
                ForEach(Array(trip.legs.enumerated()), id: \.element.id) { legIdx, leg in
                    legRow(for: leg)

                    if legIdx < trip.legs.count - 1 {
                        if let transfer = nextRailTransfer(from: legIdx) {
                            let leg1 = leg
                            let leg2 = trip.legs[transfer.nextRailIndex]
                            let arrDelay = arrivalDelay(for: leg1)
                            let depDelay = departureDelay(for: leg2)
                            let leg2Cancelled = isCancelled(leg2)
                            let hasLiveData = results[leg1.train_number] != nil && results[leg2.train_number] != nil

                            FollowedTripTransferIndicatorView(
                                stationName: leg1.destination,
                                arrTime: leg1.arrival_time,
                                arrDelay: arrDelay,
                                depTime: leg2.departure_time,
                                depDelay: depDelay,
                                walkMinutes: transfer.walkMinutes,
                                isNextTrainCancelled: leg2Cancelled,
                                hasLiveData: hasLiveData
                            )
                        } else {
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
            }
        }
        .padding(.vertical, 6)
        .task(id: trip.id) {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
        .sheet(item: $selectedTrain) { t in
            NavigationStack {
                TrainStopsView(train: t, showCloseButton: true)
                    .environmentObject(manager)
                    .environmentObject(passanteManager)
                    .environmentObject(locationManager)
                    .environmentObject(cache)
                    .environmentObject(usageTracker)
            }
        }
        .sheet(isPresented: $showTripDetails) {
            NavigationStack {
                TravelSolutionDetailsView(solution: trip.toTravelSolution(), showCloseButton: true)
                    .environmentObject(manager)
                    .environmentObject(passanteManager)
                    .environmentObject(locationManager)
                    .environmentObject(cache)
                    .environmentObject(usageTracker)
            }
        }
    }

    private var headerView: some View {
        let firstLeg = trip.legs.first
        let lastLeg = trip.legs.last
        let origin = firstLeg?.origin ?? trip.alternative.station
        let destination = lastLeg?.destination ?? trip.alternative.destination
        let depTime = firstLeg?.departure_time ?? trip.alternative.departure_time
        let arrTime = lastLeg?.arrival_time ?? trip.alternative.arrival_time ?? "--:--"

        return HStack(alignment: .center, spacing: 10) {
            Button {
                Haptics.play(.light)
                showTripDetails = true
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Il tuo viaggio")
                            .font(.headline)
                            .foregroundColor(.orange)
                        HStack(spacing: 4) {
                            Text("\(origin) → \(destination)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            if !depTime.isEmpty && depTime != "--:--" {
                                Text("· \(depTime)–\(arrTime)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    Haptics.play(.light)
                    showTripDetails = true
                } label: {
                    Label("Dettagli viaggio", systemImage: "doc.text.magnifyingglass")
                }

                Button(role: .destructive) {
                    Haptics.play(.medium)
                    commuteManager.stopFollowing(manager: manager)
                } label: {
                    Label("Smetti di seguire", systemImage: "xmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func legRow(for leg: PlanBLegItem) -> some View {
        let isWalk = leg.is_station_walk == true || leg.category.contains("piedi") || leg.train_number.contains("piedi")
        if leg.isRailTrain {
            railLegRow(for: leg)
        } else {
            nonRailLegRow(for: leg, isWalk: isWalk)
        }
    }

    private func railLegRow(for leg: PlanBLegItem) -> some View {
        let cleanCat = cleanTrainCategory(leg.category)
        let displayCatNum = cleanCat.isEmpty ? leg.train_number : "\(cleanCat) \(leg.train_number)"
        let depDelay = departureDelay(for: leg)
        let arrDelay = arrivalDelay(for: leg)
        let cancelled = isCancelled(leg)
        let platformText = resolvedPlatform(for: leg)
        let trainObj = Train(
            category: cleanCat,
            number: leg.train_number,
            destination: leg.destination,
            time: leg.departure_time,
            delay: depDelay > 0 ? "+\(depDelay)'" : "0",
            platform: platformText
        )

        return Button {
            Haptics.play(.light)
            selectedTrain = trainObj
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "tram.fill")
                        .foregroundColor(.blue)
                    Text(displayCatNum)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    Spacer()

                    if cancelled {
                        Text("Soppresso")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.18))
                            .cornerRadius(4)
                    } else if depDelay > 0 {
                        Text("ritardo \(depDelay) min.")
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

                    if !platformText.isEmpty && platformText != "--" {
                        Text("Bin. \(platformText)")
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
                        Text("Da: \(leg.origin)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("A: \(leg.destination)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        timeDisplay(scheduled: leg.departure_time, delay: depDelay)
                        timeDisplay(scheduled: leg.arrival_time, delay: arrDelay)
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
        .contextMenu {
            Button {
                Haptics.play(.light)
                selectedTrain = trainObj
            } label: {
                Label("Vista dettagli", systemImage: "tram.fill")
            }

            let isFav = manager.favoriteTrains.contains(where: { $0.number == leg.train_number })
            Button {
                let desc = "\(leg.origin) - \(leg.destination)"
                manager.toggleFavorite(trainNumber: leg.train_number, description: desc, departureTime: leg.departure_time)
                Haptics.play(.medium)
            } label: {
                Label(isFav ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti", systemImage: isFav ? "star.slash.fill" : "star.fill")
            }
        } preview: {
            FollowedTripLegPreview(leg: leg, result: results[leg.train_number])
        }
    }

    @ViewBuilder
    private func timeDisplay(scheduled: String, delay: Int) -> some View {
        if delay > 0 && CommuteTimeBand.parseHHmm(scheduled) != nil {
            let expected = TrainManager.addMinutesToTime(scheduled, delay)
            HStack(spacing: 4) {
                Text(scheduled)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .strikethrough()
                Text(expected)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
            }
        } else {
            Text(scheduled)
                .font(.caption)
                .fontWeight(.bold)
        }
    }

    private func nonRailLegRow(for leg: PlanBLegItem, isWalk: Bool) -> some View {
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

    // MARK: - Live Helpers

    private func refresh() async {
        let railLegs = trip.railLegs
        guard !railLegs.isEmpty else { return }

        var fetched: [String: StopsResult] = [:]
        await withTaskGroup(of: (String, StopsResult).self) { group in
            for leg in railLegs {
                group.addTask {
                    let res = await manager.fetchLiveStops(
                        for: leg.train_number,
                        category: leg.category,
                        destination: leg.destination,
                        origin: leg.origin,
                        scheduledTime: leg.departure_time,
                        force: true
                    )
                    return (leg.train_number, res)
                }
            }
            for await (num, res) in group {
                if res.errorMessage == nil {
                    fetched[num] = res
                }
            }
        }

        if !fetched.isEmpty {
            for (num, res) in fetched {
                results[num] = res
            }
            commuteManager.handleFollowedTripResults(results, manager: manager)
        }
    }

    private func nextRailTransfer(from index: Int) -> (nextRailIndex: Int, walkMinutes: Int)? {
        guard index < trip.legs.count - 1, trip.legs[index].isRailTrain else { return nil }
        var walkMinutes = 0
        var idx = index + 1
        while idx < trip.legs.count {
            let candidate = trip.legs[idx]
            let isWalk = candidate.is_station_walk == true || candidate.category.contains("piedi") || candidate.train_number.contains("piedi")
            if isWalk {
                walkMinutes += candidate.travel_minutes ?? 1
                idx += 1
                continue
            }
            if candidate.isRailTrain {
                return (idx, walkMinutes)
            }
            return nil
        }
        return nil
    }

    private func stop(for station: String, in result: StopsResult) -> Stop? {
        result.stops.first { planBStationMatch($0.stationName, station) }
    }

    private func arrivalDelay(for leg: PlanBLegItem) -> Int {
        guard let res = results[leg.train_number] else { return leg.delay }
        if let destStop = stop(for: leg.destination, in: res) {
            return destStop.delay
        }
        if res.status.isDeparted, let lastDelay = res.stops.last?.delay {
            return lastDelay
        }
        return leg.delay
    }

    private func departureDelay(for leg: PlanBLegItem) -> Int {
        guard let res = results[leg.train_number] else { return leg.delay }
        if let origStop = stop(for: leg.origin, in: res) {
            return origStop.delay
        }
        return leg.delay
    }

    private func isCancelled(_ leg: PlanBLegItem) -> Bool {
        guard let res = results[leg.train_number] else { return false }
        if res.status.statusMessage.contains("Soppresso") { return true }
        if let origStop = stop(for: leg.origin, in: res), origStop.isSuppressed { return true }
        if let destStop = stop(for: leg.destination, in: res), destStop.isSuppressed { return true }
        return false
    }

    private func resolvedPlatform(for leg: PlanBLegItem) -> String {
        if let res = results[leg.train_number], let origStop = stop(for: leg.origin, in: res) {
            if let actual = origStop.actualPlatform, !actual.isEmpty, actual != "--" {
                return actual
            }
            if let planned = origStop.plannedPlatform, !planned.isEmpty, planned != "--" {
                return planned
            }
        }
        return leg.platform
    }

    static func transferMargin(arr: String, arrDelay: Int, dep: String, depDelay: Int, walk: Int) -> Int? {
        guard let arrMins = CommuteTimeBand.parseHHmm(arr),
              let depMins = CommuteTimeBand.parseHHmm(dep) else {
            return nil
        }
        var margin = (depMins + depDelay) - (arrMins + arrDelay) - walk
        if margin < -720 {
            margin += 1440
        }
        return margin
    }
}

struct FollowedTripTransferIndicatorView: View {
    let stationName: String
    let arrTime: String
    let arrDelay: Int
    let depTime: String
    let depDelay: Int
    let walkMinutes: Int
    let isNextTrainCancelled: Bool
    let hasLiveData: Bool

    var body: some View {
        let margin = FollowedTripCardView.transferMargin(
            arr: arrTime,
            arrDelay: arrDelay,
            dep: depTime,
            depDelay: depDelay,
            walk: walkMinutes
        )
        let badge = badgeStyle(margin: margin)

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(badge.color)

                Text("Cambio a \(stationName)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                Text(badge.label)
                    .font(.caption2.bold())
                    .foregroundColor(badge.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badge.color.opacity(0.15))
                    .clipShape(Capsule())
            }

            if let arrExp = expectedTime(arrTime, delay: arrDelay),
               let depExp = expectedTime(depTime, delay: depDelay) {
                Text("Arrivi alle \(arrExp) · parte alle \(depExp)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemGroupedBackground).opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func badgeStyle(margin: Int?) -> (label: String, color: Color) {
        if isNextTrainCancelled {
            return ("Treno soppresso", .red)
        }
        guard let margin = margin else {
            return ("Cambio a \(stationName)", .secondary)
        }
        if !hasLiveData {
            return ("Cambio · \(margin) min", .secondary)
        }
        if margin >= 5 {
            return ("Coincidenza OK · \(margin) min", .green)
        } else if margin >= 2 {
            return ("Cambio stretto · \(margin) min", .orange)
        } else {
            return ("Coincidenza a rischio", .red)
        }
    }

    private func expectedTime(_ scheduled: String, delay: Int) -> String? {
        guard CommuteTimeBand.parseHHmm(scheduled) != nil else { return nil }
        return delay > 0 ? TrainManager.addMinutesToTime(scheduled, delay) : scheduled
    }
}

private struct FollowedTripLegPreview: View {
    let leg: PlanBLegItem
    let result: StopsResult?

    var body: some View {
        let cleanCat = cleanTrainCategory(leg.category)
        let title = cleanCat.isEmpty ? leg.train_number : "\(cleanCat) \(leg.train_number)"

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "tram.fill")
                    .foregroundColor(.blue)
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(leg.departure_time) → \(leg.arrival_time)")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
            }

            if let res = result {
                VStack(alignment: .leading, spacing: 3) {
                    Text(res.status.statusMessage)
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)
                    if res.status.lastStation != "--" {
                        Text("Ultimo rilevamento: \(res.status.lastStation) alle \(res.status.lastTime)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(res.stops.prefix(12)) { stop in
                        HStack {
                            Circle()
                                .fill(stop.delay > 0 ? Color.red : Color.green)
                                .frame(width: 8, height: 8)
                            Text(stop.stationName)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(stop.actualTime ?? stop.time)
                                .font(.caption.bold())
                        }
                    }
                }
            } else {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 20)
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .background(Color(.systemBackground))
    }
}
