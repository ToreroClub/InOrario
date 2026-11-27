import Foundation
import SwiftUI
import Combine
import StoreKit
import ActivityKit

// MARK: - Models

struct CommuteTimeBand: Equatable, Hashable, Sendable {
    var startMinutes: Int
    var endMinutes: Int

    nonisolated init(startMinutes: Int, endMinutes: Int) {
        self.startMinutes = ((startMinutes % 1440) + 1440) % 1440
        self.endMinutes = ((endMinutes % 1440) + 1440) % 1440
    }

    nonisolated var startHour: Int { startMinutes / 60 }
    nonisolated var startMinute: Int { startMinutes % 60 }
    nonisolated var endHour: Int { endMinutes / 60 }
    nonisolated var endMinute: Int { endMinutes % 60 }

    nonisolated var durationMinutes: Int {
        let d = (endMinutes - startMinutes + 1440) % 1440
        return d == 0 ? 60 : d
    }

    nonisolated var formatted: String {
        String(format: "%02d:%02d - %02d:%02d", startHour, startMinute, endHour, endMinute)
    }

    nonisolated var compactFormatted: String {
        String(format: "%02d:%02d-%02d:%02d", startHour, startMinute, endHour, endMinute)
    }

    nonisolated var durationLabel: String {
        let d = durationMinutes
        if d < 60 {
            return "\(d) min"
        }
        let hours = d / 60
        let mins = d % 60
        return mins == 0 ? "\(hours)h" : "\(hours)h \(mins)m"
    }

    nonisolated static func parseHHmm(_ str: String) -> Int? {
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":")
        guard parts.count >= 2,
              let hh = Int(parts[0]), (0...23).contains(hh),
              let mm = Int(parts[1].prefix(2)), (0...59).contains(mm) else {
            return nil
        }
        return hh * 60 + mm
    }

    nonisolated static func parse(
        _ raw: String,
        fallbackStart: Int = 7 * 60,
        fallbackEnd: Int = 8 * 60
    ) -> CommuteTimeBand {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return CommuteTimeBand(startMinutes: fallbackStart, endMinutes: fallbackEnd)
        }
        let parts: [String]
        if trimmed.contains(" - ") {
            parts = trimmed.components(separatedBy: " - ")
        } else if trimmed.contains("-") {
            parts = trimmed.components(separatedBy: "-")
        } else {
            parts = [trimmed]
        }

        if let start = parseHHmm(parts[0]) {
            if parts.count > 1, let end = parseHHmm(parts[1]) {
                return CommuteTimeBand(startMinutes: start, endMinutes: end)
            }
            return CommuteTimeBand(startMinutes: start, endMinutes: (start + 60) % 1440)
        }
        return CommuteTimeBand(startMinutes: fallbackStart, endMinutes: fallbackEnd)
    }

    nonisolated func updatingStart(to newStart: Int) -> CommuteTimeBand {
        let normStart = ((newStart % 1440) + 1440) % 1440
        let newDuration = (endMinutes - normStart + 1440) % 1440
        if newDuration >= 15 && newDuration <= 360 {
            return CommuteTimeBand(startMinutes: normStart, endMinutes: endMinutes)
        }
        let preserved = min(max(durationMinutes, 15), 240)
        return CommuteTimeBand(startMinutes: normStart, endMinutes: (normStart + preserved) % 1440)
    }

    nonisolated func updatingEnd(to newEnd: Int) -> CommuteTimeBand {
        let normEnd = ((newEnd % 1440) + 1440) % 1440
        let diff = (normEnd - startMinutes + 1440) % 1440
        if diff >= 15 && diff <= 360 {
            return CommuteTimeBand(startMinutes: startMinutes, endMinutes: normEnd)
        }
        return CommuteTimeBand(startMinutes: startMinutes, endMinutes: (startMinutes + 15) % 1440)
    }

    nonisolated func contains(timeString: String, marginBefore: Int = 0, marginAfter: Int = 0) -> Bool {
        guard let tMin = Self.parseHHmm(timeString) else { return false }
        let dur = durationMinutes
        var rawDiff = tMin - startMinutes
        if rawDiff < -720 {
            rawDiff += 1440
        } else if rawDiff > 720 {
            rawDiff -= 1440
        }
        return rawDiff >= -marginBefore && rawDiff <= dur + marginAfter
    }

    nonisolated static func date(forMinutes minutes: Int, calendar: Calendar = .current) -> Date {
        let norm = ((minutes % 1440) + 1440) % 1440
        var comps = calendar.dateComponents([.year, .month, .day], from: Date())
        comps.hour = norm / 60
        comps.minute = norm % 60
        comps.second = 0
        return calendar.date(from: comps) ?? Date()
    }

    nonisolated static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }
}

struct CommuteHabitTrain: Codable, Equatable, Identifiable, Hashable, Sendable {
    var trainNumber: String
    var category: String
    var originStation: String
    var destinationStation: String
    var departureTime: String
    var arrivalTime: String?
    var isManuallyAdded: Bool

    nonisolated var id: String {
        "\(trainNumber)_\(originStation.lowercased())_\(departureTime)"
    }

    nonisolated init(
        trainNumber: String,
        category: String = "Treno",
        originStation: String,
        destinationStation: String,
        departureTime: String,
        arrivalTime: String? = nil,
        isManuallyAdded: Bool = false
    ) {
        self.trainNumber = trainNumber
        self.category = category
        self.originStation = originStation
        self.destinationStation = destinationStation
        self.departureTime = departureTime
        self.arrivalTime = arrivalTime
        self.isManuallyAdded = isManuallyAdded
    }

    enum CodingKeys: String, CodingKey {
        case trainNumber, category, originStation, destinationStation, departureTime, arrivalTime, isManuallyAdded
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trainNumber = try c.decode(String.self, forKey: .trainNumber)
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "Treno"
        originStation = try c.decodeIfPresent(String.self, forKey: .originStation) ?? ""
        destinationStation = try c.decodeIfPresent(String.self, forKey: .destinationStation) ?? ""
        departureTime = try c.decodeIfPresent(String.self, forKey: .departureTime) ?? "--:--"
        arrivalTime = try c.decodeIfPresent(String.self, forKey: .arrivalTime)
        isManuallyAdded = try c.decodeIfPresent(Bool.self, forKey: .isManuallyAdded) ?? false
    }
}

struct DayCommuteSchedule: Codable, Equatable, Sendable {
    var isEnabled: Bool = true
    var outboundBand: String = "07:00 - 08:00"
    var returnBand: String = "17:00 - 18:00"
    var excludedOutboundOrigins: [String] = []
    var excludedOutboundDestinations: [String] = []
    var excludedReturnOrigins: [String] = []
    var excludedReturnDestinations: [String] = []
    var outboundTrains: [CommuteHabitTrain] = []
    var returnTrains: [CommuteHabitTrain] = []
    var outboundTrainsCustomized: Bool = false
    var returnTrainsCustomized: Bool = false

    nonisolated init(
        isEnabled: Bool = true,
        outboundBand: String = "07:00 - 08:00",
        returnBand: String = "17:00 - 18:00",
        excludedOutboundOrigins: [String] = [],
        excludedOutboundDestinations: [String] = [],
        excludedReturnOrigins: [String] = [],
        excludedReturnDestinations: [String] = [],
        outboundTrains: [CommuteHabitTrain] = [],
        returnTrains: [CommuteHabitTrain] = [],
        outboundTrainsCustomized: Bool = false,
        returnTrainsCustomized: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.outboundBand = outboundBand
        self.returnBand = returnBand
        self.excludedOutboundOrigins = excludedOutboundOrigins
        self.excludedOutboundDestinations = excludedOutboundDestinations
        self.excludedReturnOrigins = excludedReturnOrigins
        self.excludedReturnDestinations = excludedReturnDestinations
        self.outboundTrains = outboundTrains
        self.returnTrains = returnTrains
        self.outboundTrainsCustomized = outboundTrainsCustomized
        self.returnTrainsCustomized = returnTrainsCustomized
    }

    enum CodingKeys: String, CodingKey {
        case isEnabled, outboundBand, returnBand
        case excludedOutboundOrigins, excludedOutboundDestinations
        case excludedReturnOrigins, excludedReturnDestinations
        case outboundTrains, returnTrains
        case outboundTrainsCustomized, returnTrainsCustomized
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        outboundBand = try c.decodeIfPresent(String.self, forKey: .outboundBand) ?? "07:00 - 08:00"
        returnBand = try c.decodeIfPresent(String.self, forKey: .returnBand) ?? "17:00 - 18:00"
        excludedOutboundOrigins = try c.decodeIfPresent([String].self, forKey: .excludedOutboundOrigins) ?? []
        excludedOutboundDestinations = try c.decodeIfPresent([String].self, forKey: .excludedOutboundDestinations) ?? []
        excludedReturnOrigins = try c.decodeIfPresent([String].self, forKey: .excludedReturnOrigins) ?? []
        excludedReturnDestinations = try c.decodeIfPresent([String].self, forKey: .excludedReturnDestinations) ?? []
        outboundTrains = try c.decodeIfPresent([CommuteHabitTrain].self, forKey: .outboundTrains) ?? []
        returnTrains = try c.decodeIfPresent([CommuteHabitTrain].self, forKey: .returnTrains) ?? []
        outboundTrainsCustomized = try c.decodeIfPresent(Bool.self, forKey: .outboundTrainsCustomized) ?? false
        returnTrainsCustomized = try c.decodeIfPresent(Bool.self, forKey: .returnTrainsCustomized) ?? false
    }

    nonisolated var hasCustomStationExclusions: Bool {
        !excludedOutboundOrigins.isEmpty ||
        !excludedOutboundDestinations.isEmpty ||
        !excludedReturnOrigins.isEmpty ||
        !excludedReturnDestinations.isEmpty
    }
}

struct CommuteScheduleDTO: Codable, Identifiable, Equatable {
    var id: String { "\(type)_\(time)" }
    var type: String // "outbound" or "return"
    var time: String // "HH:mm - HH:mm"
    var weekdays: [Int] // 1=Mon .. 7=Sun
}

nonisolated func planBStationMatch(_ s1: String, _ s2: String) -> Bool {
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

struct PlanBLegItem: Codable, Identifiable, Equatable {
    var id: String { "\(train_number)_\(departure_time)_\(origin)_\(destination)" }
    let train_number: String
    let category: String
    let origin: String
    let destination: String
    let departure_time: String
    let arrival_time: String
    let delay: Int
    let platform: String
    let is_urban: Bool
    var is_station_walk: Bool?
    var travel_minutes: Int?
    var urban_headsign: String?

    var isRailTrain: Bool {
        let isWalk = is_station_walk == true || category.contains("piedi") || train_number.contains("piedi")
        return !isWalk && !is_urban
    }
}

struct FollowedTrip: Codable, Equatable, Identifiable {
    var id: String { "\(alternative.id)_\(dayKey)" }
    let alternative: PlanBAlternativeItem
    let legs: [PlanBLegItem]
    let dayKey: String
    let createdAt: Date

    var railLegs: [PlanBLegItem] { legs.filter { $0.isRailTrain } }
    var isSingleTrain: Bool { railLegs.count == 1 }
    var isExpired: Bool { dayKey != DateFormatter.todayString() }

    static func from(solution: TravelSolution) -> FollowedTrip {
        let mappedLegs: [PlanBLegItem]
        if solution.segments.isEmpty {
            mappedLegs = [
                PlanBLegItem(
                    train_number: solution.trainNumber,
                    category: solution.category,
                    origin: solution.origin,
                    destination: solution.destination,
                    departure_time: solution.departureTime,
                    arrival_time: solution.arrivalTime,
                    delay: 0,
                    platform: "",
                    is_urban: solution.category == "Trasporto Urbano" || solution.category.contains("Metro"),
                    is_station_walk: solution.category == "Interscambio a piedi",
                    travel_minutes: nil,
                    urban_headsign: nil
                )
            ]
        } else {
            mappedLegs = solution.segments.map { seg in
                let isWalk = seg.isStationWalk || seg.trainCategory == "Interscambio a piedi"
                let isUrban = seg.trainCategory == "Trasporto Urbano" || seg.trainCategory.contains("Metro")
                return PlanBLegItem(
                    train_number: seg.trainNumber,
                    category: seg.trainCategory,
                    origin: seg.origin,
                    destination: seg.destination,
                    departure_time: seg.departureTime,
                    arrival_time: seg.arrivalTime,
                    delay: 0,
                    platform: "",
                    is_urban: isUrban,
                    is_station_walk: isWalk,
                    travel_minutes: seg.travelMinutes,
                    urban_headsign: seg.urbanHeadsign
                )
            }
        }

        let firstTrainLeg = mappedLegs.first(where: { $0.isRailTrain }) ?? mappedLegs.first
        let alt = PlanBAlternativeItem(
            train_number: firstTrainLeg?.train_number ?? solution.trainNumber,
            category: firstTrainLeg?.category ?? solution.category,
            destination: solution.destination,
            station: solution.origin,
            departure_time: solution.departureTime,
            arrival_time: solution.arrivalTime,
            duration: solution.duration,
            delay: 0,
            platform: "",
            transfer_info: mappedLegs.count > 1 ? "\(mappedLegs.count - 1) cambi" : "Diretto",
            legs: mappedLegs
        )

        return FollowedTrip(
            alternative: alt,
            legs: mappedLegs,
            dayKey: DateFormatter.todayString(),
            createdAt: Date()
        )
    }

    func toTravelSolution() -> TravelSolution {
        let segs: [TravelSegment] = legs.map { leg in
            let isWalk = leg.is_station_walk == true || leg.category.contains("piedi") || leg.train_number.contains("piedi")
            return TravelSegment(
                origin: leg.origin,
                destination: leg.destination,
                departureTime: leg.departure_time,
                arrivalTime: leg.arrival_time,
                trainNumber: leg.train_number,
                trainCategory: leg.category,
                travelMinutes: leg.travel_minutes,
                urbanHeadsign: leg.urban_headsign,
                isStationWalk: isWalk
            )
        }
        let firstLeg = legs.first
        let lastLeg = legs.last
        let origin = firstLeg?.origin ?? alternative.station
        let destination = lastLeg?.destination ?? alternative.destination
        let depTime = firstLeg?.departure_time ?? alternative.departure_time
        let arrTime = lastLeg?.arrival_time ?? alternative.arrival_time ?? "--:--"
        let duration = alternative.duration ?? TrainManager.calculateDurationBetween(dep: depTime, arr: arrTime) ?? "--"
        return TravelSolution(
            trainNumber: alternative.train_number,
            category: alternative.category,
            departureTime: depTime,
            arrivalTime: arrTime,
            origin: origin,
            destination: destination,
            duration: duration,
            segments: segs
        )
    }
}

struct PlanBAlternativeItem: Codable, Identifiable, Equatable {
    var id: String { "\(train_number)_\(departure_time)_\(station)" }
    let train_number: String
    let category: String
    let destination: String
    let station: String
    let departure_time: String
    var arrival_time: String?
    var duration: String?
    let delay: Int
    let platform: String
    let transfer_info: String
    var legs: [PlanBLegItem]?

    var resolvedLegs: [PlanBLegItem] {
        if let l = legs, !l.isEmpty {
            let cleaned = l.filter { !planBStationMatch($0.origin, $0.destination) }
            if !cleaned.isEmpty { return cleaned }
        }
        return [
            PlanBLegItem(
                train_number: train_number,
                category: category,
                origin: station,
                destination: destination,
                departure_time: departure_time,
                arrival_time: arrival_time ?? "--:--",
                delay: delay,
                platform: platform,
                is_urban: train_number.contains("M1") || category.contains("Metro"),
                is_station_walk: false,
                travel_minutes: nil,
                urban_headsign: nil
            )
        ]
    }

    var compactTrainsSummary: String {
        let nonWalkLegs = resolvedLegs.filter { !($0.is_station_walk == true || $0.category.lowercased().contains("piedi")) }
        let formatted = nonWalkLegs.compactMap { leg -> String? in
            if leg.is_urban {
                let c = leg.category.trimmingCharacters(in: .whitespacesAndNewlines)
                return c.isEmpty ? "Metro" : c
            }
            let cleanCat = cleanTrainCategory(leg.category)
            let num = leg.train_number.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanCat.isEmpty && num.isEmpty { return nil }
            return cleanCat.isEmpty ? num : "\(cleanCat) \(num)"
        }
        if !formatted.isEmpty {
            return formatted.joined(separator: " + ")
        }
        let cleanCat = cleanTrainCategory(category)
        return cleanCat.isEmpty ? train_number : "\(cleanCat) \(train_number)"
    }

    func toTravelSolution() -> TravelSolution {
        let legs = resolvedLegs
        let segs: [TravelSegment] = legs.map { leg in
            let isWalk = leg.is_station_walk == true || leg.category.lowercased().contains("piedi") || leg.train_number.lowercased().contains("piedi")
            return TravelSegment(
                origin: leg.origin,
                destination: leg.destination,
                departureTime: leg.departure_time,
                arrivalTime: leg.arrival_time,
                trainNumber: leg.train_number,
                trainCategory: leg.category,
                travelMinutes: leg.travel_minutes,
                urbanHeadsign: leg.urban_headsign,
                isStationWalk: isWalk
            )
        }
        let firstLeg = legs.first
        let lastLeg = legs.last
        let orig = firstLeg?.origin ?? station
        let dest = lastLeg?.destination ?? destination
        let dep = firstLeg?.departure_time ?? departure_time
        let arr = lastLeg?.arrival_time ?? arrival_time ?? "--:--"
        let dur = duration ?? TrainManager.calculateDurationBetween(dep: dep, arr: arr) ?? "--"
        let cleanCat = cleanTrainCategory(firstLeg?.category ?? category)
        return TravelSolution(
            trainNumber: firstLeg?.train_number ?? train_number,
            category: cleanCat.isEmpty ? (firstLeg?.category ?? category) : cleanCat,
            departureTime: dep,
            arrivalTime: arr,
            origin: orig,
            destination: dest,
            duration: dur,
            segments: segs
        )
    }
}

struct ActiveHabitCommuteSlot: Equatable {
    let isReturn: Bool
    let origins: [String]
    let destinations: [String]
    let timeBand: String
}

struct PlanBReportDTO: Codable, Identifiable, Equatable {
    var id: String { timestamp }
    let title: String
    let body: String
    let incident_type: String?
    let incident_detail: String?
    let cancelled_train: String?
    let target_time: String
    let origins: [String]
    let destinations: [String]
    let alternatives: [PlanBAlternativeItem]
    let timestamp: String
}

struct CachedProactiveHabitPlan: Codable, Equatable {
    let slotKey: String
    let dayKey: String
    let fetchedAt: Date
    let plan: PlanBReportDTO
}

// MARK: - City/Station Formatter

nonisolated func formatCityOrStationSummary(_ stations: [String]) -> String {
    guard !stations.isEmpty else { return "" }

    func cleanStationDisplay(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("milano ") {
            let rest = trimmed.dropFirst(7).trimmingCharacters(in: .whitespaces)
            return "Milano \(rest.capitalized)"
        }
        return trimmed.capitalized
    }

    func extractCityPrefix(_ station: String) -> String? {
        let words = station
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard let first = words.first else { return nil }
        let twoWordPrefixes: Set<String> = [
            "san", "santa", "sant'", "santo", "reggio", "busto", "ponte",
            "villa", "porto", "castel", "castello", "monte", "borgo", "torre",
            "casal", "casale", "cava", "sesto", "cesano", "novate", "paderno",
            "abbiate", "cinisello", "garbagnate", "cormano", "bollate",
            "trezzano", "pioltello"
        ]
        if twoWordPrefixes.contains(first.lowercased()), words.count >= 2 {
            return "\(words[0]) \(words[1])"
        }
        if first.count >= 3 {
            return first
        }
        return nil
    }

    let cleanedStations = stations.map(cleanStationDisplay)
    if cleanedStations.count == 1 { return cleanedStations[0] }

    if let candidateCity = extractCityPrefix(cleanedStations[0]) {
        let lowerCandidate = candidateCity.lowercased()
        let prefixWithSpace = lowerCandidate + " "
        let allShareCity = cleanedStations.allSatisfy { st in
            let lower = st.lowercased()
            return lower == lowerCandidate || lower.hasPrefix(prefixWithSpace)
        }
        if allShareCity {
            return candidateCity
        }
    }

    if cleanedStations.count <= 2 {
        return cleanedStations.joined(separator: ", ")
    } else {
        return "\(cleanedStations[0]), \(cleanedStations[1]) +\(cleanedStations.count - 2)"
    }
}

// MARK: - Supporter Commute Manager

@MainActor
class SupporterCommuteManager: ObservableObject {
    static let shared = SupporterCommuteManager()
    
    static let maxStationsPerSide = 3

    nonisolated static func canAddStation(currentCount: Int, isPro: Bool) -> Bool {
        isPro || currentCount < maxStationsPerSide
    }

    static let timeBands: [String] = [
        "05:00 - 06:00",
        "06:00 - 07:00",
        "07:00 - 08:00",
        "08:00 - 09:00",
        "09:00 - 10:00",
        "10:00 - 11:00",
        "11:00 - 12:00",
        "12:00 - 13:00",
        "13:00 - 14:00",
        "14:00 - 15:00",
        "15:00 - 16:00",
        "16:00 - 17:00",
        "17:00 - 18:00",
        "18:00 - 19:00",
        "19:00 - 20:00",
        "20:00 - 21:00",
        "21:00 - 22:00",
        "22:00 - 23:00",
        "23:00 - 00:00"
    ]
    
    // Persisted State
    @AppStorage("commute_origins_v1") private var originsRaw: String = ""
    @AppStorage("commute_destinations_v1") private var destinationsRaw: String = ""
    @AppStorage("commute_outbound_band_v2") var defaultOutboundBand: String = "07:00 - 08:00"
    @AppStorage("commute_return_band_v2") var defaultReturnBand: String = "17:00 - 18:00"
    @AppStorage("commute_weekdays_v1") private var weekdaysRaw: String = "1,2,3,4,5"
    @AppStorage("commute_customize_per_day_v1") var customizePerDay: Bool = false
    @AppStorage("commute_day_schedules_json_v1") private var daySchedulesJSON: String = ""
    @AppStorage("commute_proactive_alerts_v1") var proactiveAlertsEnabled: Bool = true
    @AppStorage("commute_scheduled_summary_enabled_v1") var scheduledSummaryEnabled: Bool = false
    @AppStorage("commute_scheduled_summary_mode_v1") var scheduledSummaryMode: String = "always"
    @AppStorage("commute_scheduled_summary_excluded_days_v1") private var scheduledSummaryExcludedDaysRaw: String = ""
    @AppStorage("commute_scheduled_summary_lead_minutes_v1") var scheduledSummaryLeadMinutes: Int = 30
    @AppStorage("commute_scheduled_summary_scope_v1") var scheduledSummaryScope: String = "both"
    @AppStorage("commute_prompt_snoozed_until_v1") private var snoozedUntilDouble: Double = 0
    @AppStorage("commute_prompt_permanently_dismissed_v1") var promptPermanentlyDismissed: Bool = false
    @AppStorage("pinned_plan_b_json_v1") private var pinnedPlanBJSON: String = ""
    @AppStorage("commute_chosen_alternative_id_v1") private var chosenAlternativeIdRaw: String = ""
    @AppStorage("commute_followed_trip_json_v1") private var followedTripJSON: String = ""
    @AppStorage("commute_proactive_habit_cache_v1") private var proactiveHabitCacheJSON: String = ""
    @AppStorage("commute_manual_dir_override_v1") private var manualDirectionOverrideRaw: String = ""
    
    @Published var origins: [String] = [] {
        didSet { saveOrigins() }
    }
    @Published var destinations: [String] = [] {
        didSet { saveDestinations() }
    }
    @Published var activeWeekdays: Set<Int> = [1, 2, 3, 4, 5] {
        didSet { saveWeekdays() }
    }
    @Published var daySchedules: [Int: DayCommuteSchedule] = [:] {
        didSet { saveDaySchedules() }
    }
    @Published var scheduledSummaryExcludedWeekdays: Set<Int> = [] {
        didSet { saveScheduledSummaryExcludedDays() }
    }
    
    // Active Plan B received from server or manual check
    @Published var activePlanB: PlanBReportDTO? = nil
    @Published var pinnedPlanB: PlanBReportDTO? = nil
    @Published var pendingOpenPlanBSheet: Bool = false
    @Published var chosenAlternativeId: String? = nil {
        didSet { chosenAlternativeIdRaw = chosenAlternativeId ?? "" }
    }
    @Published var followedTrip: FollowedTrip? = nil {
        didSet {
            if let trip = followedTrip,
               let data = try? JSONEncoder().encode(trip),
               let str = String(data: data, encoding: .utf8) {
                followedTripJSON = str
            } else {
                followedTripJSON = ""
            }
        }
    }
    @Published var isCalculatingPlanB: Bool = false
    @Published var isCalculatingCommuteSolutions: Bool = false
    @Published var lastSyncError: String? = nil

    var hasConfiguredCommute: Bool {
        !origins.isEmpty && !destinations.isEmpty
    }
    @Published var cachedProactiveHabitPlan: PlanBReportDTO? = nil
    @Published var cachedProactiveHabitSlotKey: String = ""
    @Published var cachedProactiveHabitDayKey: String = ""
    @Published var cachedProactiveHabitFetchedAt: Date? = nil
    private var lastFollowedTripRefreshAt: Date? = nil
    private var lastObservedSupport: Bool = false

    /// Plan B to display in the Home screen "Nelle vicinanze" strip.
    /// Regular commute summaries (`summary_ok`) and test simulations (`simulation`) are hidden
    /// unless the user explicitly tapped "Segui" on one of the train options.
    var homeBannerPlanB: PlanBReportDTO? {
        guard followedTrip == nil else { return nil }
        guard hasSupport() else { return nil }
        guard let plan = pinnedPlanB ?? activePlanB else { return nil }
        if let chosenId = chosenAlternativeId, !chosenId.isEmpty,
           plan.alternatives.contains(where: {
               $0.id == chosenId || chosenId.hasPrefix("\($0.train_number)_\($0.departure_time)")
           }) {
            return plan
        }
        if plan.incident_type == "summary_ok" || plan.incident_type == "simulation" {
            return nil
        }
        return plan
    }
    
    private init() {
        loadData()
        lastObservedSupport = hasSupport()
        NotificationCenter.default.addObserver(forName: NSNotification.Name("PurchasesUpdated"), object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.handlePurchasesUpdated()
            }
        }
    }

    func handlePurchasesUpdated() async {
        self.objectWillChange.send()
        let currentSupport = hasSupport()
        let changed = (currentSupport != lastObservedSupport)
        lastObservedSupport = currentSupport

        if !currentSupport {
            if activePlanB != nil || pinnedPlanB != nil || pendingOpenPlanBSheet {
                activePlanB = nil
                unpinPlanB()
                pendingOpenPlanBSheet = false
            }
            if changed && !origins.isEmpty && !destinations.isEmpty {
                await syncRoutineWithServer(allowRevocationWhenUnsupported: true)
            }
        } else if changed && !origins.isEmpty && !destinations.isEmpty {
            await syncRoutineWithServer()
        }
    }
    
    func loadData() {
        if !originsRaw.isEmpty {
            origins = originsRaw.components(separatedBy: "|||").filter { !$0.isEmpty }
        }
        if !destinationsRaw.isEmpty {
            destinations = destinationsRaw.components(separatedBy: "|||").filter { !$0.isEmpty }
        }
        let days = weekdaysRaw.components(separatedBy: ",").compactMap { Int($0) }
        if !days.isEmpty {
            activeWeekdays = Set(days)
        }

        if !scheduledSummaryExcludedDaysRaw.isEmpty {
            let excl = scheduledSummaryExcludedDaysRaw.components(separatedBy: ",").compactMap { Int($0) }
            scheduledSummaryExcludedWeekdays = Set(excl)
        }
        
        // Carica orari per singolo giorno
        if !daySchedulesJSON.isEmpty,
           let data = daySchedulesJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([Int: DayCommuteSchedule].self, from: data) {
            daySchedules = decoded
        } else {
            initDefaultDaySchedules()
        }
        
        // Carica eventuale percorso salvato in Home
        if !pinnedPlanBJSON.isEmpty,
           let data = pinnedPlanBJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(PlanBReportDTO.self, from: data) {
            pinnedPlanB = decoded
        }
        
        if !chosenAlternativeIdRaw.isEmpty {
            chosenAlternativeId = chosenAlternativeIdRaw
        }
        
        if !followedTripJSON.isEmpty,
           let data = followedTripJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(FollowedTrip.self, from: data),
           !decoded.isExpired {
            followedTrip = decoded
        } else {
            followedTrip = nil
        }

        if !proactiveHabitCacheJSON.isEmpty,
           let data = proactiveHabitCacheJSON.data(using: .utf8),
           let cached = try? JSONDecoder().decode(CachedProactiveHabitPlan.self, from: data),
           Self.hasValidUpcomingCachedSolutions(plan: cached.plan, dayKey: cached.dayKey) {
            cachedProactiveHabitPlan = cached.plan
            cachedProactiveHabitSlotKey = cached.slotKey
            cachedProactiveHabitDayKey = cached.dayKey
            cachedProactiveHabitFetchedAt = cached.fetchedAt
        } else {
            cachedProactiveHabitPlan = nil
            cachedProactiveHabitSlotKey = ""
            cachedProactiveHabitDayKey = ""
            cachedProactiveHabitFetchedAt = nil
        }
    }
    
    private func initDefaultDaySchedules() {
        var dict: [Int: DayCommuteSchedule] = [:]
        for d in 1...7 {
            let isWorkday = (1...5).contains(d)
            dict[d] = DayCommuteSchedule(
                isEnabled: isWorkday,
                outboundBand: defaultOutboundBand,
                returnBand: defaultReturnBand
            )
        }
        daySchedules = dict
    }
    
    private func saveOrigins() {
        originsRaw = origins.joined(separator: "|||")
    }
    
    private func saveDestinations() {
        destinationsRaw = destinations.joined(separator: "|||")
    }
    
    private func saveWeekdays() {
        weekdaysRaw = activeWeekdays.sorted().map { String($0) }.joined(separator: ",")
    }
    
    private func saveDaySchedules() {
        if let data = try? JSONEncoder().encode(daySchedules),
           let str = String(data: data, encoding: .utf8) {
            daySchedulesJSON = str
        }
    }

    private func saveScheduledSummaryExcludedDays() {
        scheduledSummaryExcludedDaysRaw = scheduledSummaryExcludedWeekdays.sorted().map { String($0) }.joined(separator: ",")
    }
    
    func pinPlanB(_ plan: PlanBReportDTO) {
        pinnedPlanB = plan
        if let data = try? JSONEncoder().encode(plan),
           let str = String(data: data, encoding: .utf8) {
            pinnedPlanBJSON = str
        }
    }
    
    func unpinPlanB() {
        pinnedPlanB = nil
        pinnedPlanBJSON = ""
    }
    
    func toggleChosenAlternative(id: String) {
        if chosenAlternativeId == id {
            chosenAlternativeId = nil
        } else {
            chosenAlternativeId = id
        }
    }
    
    func followAlternative(_ alt: PlanBAlternativeItem, legs: [PlanBLegItem]) {
        followedTrip = FollowedTrip(
            alternative: alt,
            legs: legs,
            dayKey: DateFormatter.todayString(),
            createdAt: Date()
        )
        chosenAlternativeId = nil
    }
    
    func followSolution(_ solution: TravelSolution) {
        followedTrip = FollowedTrip.from(solution: solution)
        chosenAlternativeId = nil
    }
    
    func isSolutionFollowed(_ solution: TravelSolution) -> Bool {
        guard let current = followedTrip else { return false }
        let candidate = FollowedTrip.from(solution: solution)
        return current.alternative.id == candidate.alternative.id && !current.isExpired
    }
    
    func clearPlanBAfterFollow() {
        chosenAlternativeId = nil
        pendingOpenPlanBSheet = false
        if let incType = activePlanB?.incident_type,
           incType == "summary_ok" || incType == "simulation" {
            activePlanB = nil
        }
    }
    
    private func clearCompletedPlanB() {
        unpinPlanB()
        activePlanB = nil
        chosenAlternativeId = nil
        pendingOpenPlanBSheet = false
    }
    
    func stopFollowing(manager: TrainManager, immediate: Bool = true) {
        if let trip = followedTrip, trip.isSingleTrain, let railLeg = trip.railLegs.first {
            let targetNum = railLeg.train_number.trimmingCharacters(in: .whitespacesAndNewlines)
            let policy: ActivityUIDismissalPolicy = immediate ? .immediate : .default
            let matching = Activity<TrainLiveActivityAttributes>.activities.filter {
                $0.attributes.trainNumber == targetNum
            }
            if !matching.isEmpty {
                Task { @MainActor in
                    for activity in matching {
                        await activity.end(nil, dismissalPolicy: policy)
                    }
                    manager.syncLiveActivities()
                }
            }
        }
        followedTrip = nil
    }
    
    func refreshFollowedTripStatus(manager: TrainManager, force: Bool = false, minInterval: TimeInterval = 120) async {
        guard let trip = followedTrip else { return }
        if trip.isExpired {
            stopFollowing(manager: manager, immediate: false)
            clearCompletedPlanB()
            return
        }
        if !force, let last = lastFollowedTripRefreshAt, Date().timeIntervalSince(last) < minInterval {
            return
        }
        lastFollowedTripRefreshAt = Date()
        guard let lastLeg = trip.railLegs.last else { return }
        let res = await manager.fetchLiveStops(
            for: lastLeg.train_number,
            category: lastLeg.category,
            destination: lastLeg.destination,
            origin: lastLeg.origin,
            scheduledTime: lastLeg.departure_time,
            force: force
        )
        if res.errorMessage == nil && res.status.isArrived {
            stopFollowing(manager: manager, immediate: false)
            clearCompletedPlanB()
        }
    }
    
    func handleFollowedTripResults(_ results: [String: StopsResult], manager: TrainManager) {
        guard let trip = followedTrip else { return }
        if trip.isExpired {
            stopFollowing(manager: manager, immediate: false)
            clearCompletedPlanB()
            return
        }
        guard let lastLeg = trip.railLegs.last,
              let res = results[lastLeg.train_number],
              res.errorMessage == nil,
              res.status.isArrived else {
            return
        }
        stopFollowing(manager: manager, immediate: false)
        clearCompletedPlanB()
    }
    
    func hasSupport() -> Bool {
        return UserDefaults.standard.bool(forKey: "tip.colazionee")
    }
    
    // MARK: - Supporter Eternal ID (StoreKit 2 originalID + iCloud Sync)
    
    func getSupporterEternalID() -> String {
        // 1. Check local standard storage
        if let localID = UserDefaults.standard.string(forKey: "supporter_eternal_id"), !localID.isEmpty {
            return localID
        }
        // 2. Check iCloud Key-Value Store
        if let cloudID = NSUbiquitousKeyValueStore.default.string(forKey: "supporter_eternal_id"), !cloudID.isEmpty {
            UserDefaults.standard.set(cloudID, forKey: "supporter_eternal_id")
            return cloudID
        }
        // 3. Fallback: if user is supporter, create stable identifier synced to iCloud
        if hasSupport() {
            let fallback = "sup_dev_" + UUID().uuidString.prefix(12)
            UserDefaults.standard.set(fallback, forKey: "supporter_eternal_id")
            NSUbiquitousKeyValueStore.default.set(fallback, forKey: "supporter_eternal_id")
            return fallback
        }
        return ""
    }
    
    // MARK: - Banner Prompt Logic
    
    var shouldShowPromptBanner: Bool {
        guard hasSupport() else { return false }
        guard !promptPermanentlyDismissed else { return false }
        
        // Non mostrare se già configurato (almeno 1 origine e 1 destinazione)
        if !origins.isEmpty && !destinations.isEmpty {
            return false
        }
        
        // Verifica snooze
        let now = Date().timeIntervalSince1970
        if snoozedUntilDouble > now {
            return false
        }
        
        return true
    }
    
    func snoozePromptForTomorrow() {
        let tomorrow = Date().addingTimeInterval(86400).timeIntervalSince1970
        snoozedUntilDouble = tomorrow
    }
    
    func dismissPromptPermanently() {
        promptPermanentlyDismissed = true
    }
    
    // MARK: - Effective Per-Day Stations

    static func resolveEffectiveStations(
        baseOrigins: [String],
        baseDestinations: [String],
        schedule: DayCommuteSchedule?,
        isReturn: Bool
    ) -> (origins: [String], destinations: [String]) {
        let poolOrigins = isReturn ? baseDestinations : baseOrigins
        let poolDestinations = isReturn ? baseOrigins : baseDestinations
        guard let sched = schedule else {
            return (poolOrigins, poolDestinations)
        }
        let exclOrig = Set(isReturn ? sched.excludedReturnOrigins : sched.excludedOutboundOrigins)
        let exclDest = Set(isReturn ? sched.excludedReturnDestinations : sched.excludedOutboundDestinations)
        let filteredOrig = poolOrigins.filter { !exclOrig.contains($0) }
        let filteredDest = poolDestinations.filter { !exclDest.contains($0) }
        return (
            filteredOrig.isEmpty ? poolOrigins : filteredOrig,
            filteredDest.isEmpty ? poolDestinations : filteredDest
        )
    }

    func effectiveStations(for weekday: Int, isReturn: Bool) -> (origins: [String], destinations: [String]) {
        guard customizePerDay else {
            return isReturn ? (destinations, origins) : (origins, destinations)
        }
        return Self.resolveEffectiveStations(
            baseOrigins: origins,
            baseDestinations: destinations,
            schedule: daySchedules[weekday],
            isReturn: isReturn
        )
    }

    func effectiveTrains(for weekday: Int, isReturn: Bool) -> [CommuteHabitTrain] {
        guard let sched = daySchedules[weekday] else { return [] }
        return isReturn ? sched.returnTrains : sched.outboundTrains
    }

    // MARK: - Scheduled Summary Day Helpers

    func isCommuteDayActive(_ weekday: Int) -> Bool {
        if customizePerDay {
            return daySchedules[weekday]?.isEnabled ?? activeWeekdays.contains(weekday)
        }
        return activeWeekdays.contains(weekday)
    }

    func commuteBandsForDay(_ weekday: Int) -> (outbound: String, returnBand: String) {
        if customizePerDay, let sched = daySchedules[weekday] {
            return (sched.outboundBand, sched.returnBand)
        }
        return (defaultOutboundBand, defaultReturnBand)
    }

    func isScheduledSummaryActive(on weekday: Int) -> Bool {
        guard isCommuteDayActive(weekday) else { return false }
        let activeCommuteDays = (1...7).filter { isCommuteDayActive($0) }
        let nonExcluded = activeCommuteDays.filter { !scheduledSummaryExcludedWeekdays.contains($0) }
        if nonExcluded.isEmpty {
            return true
        }
        return !scheduledSummaryExcludedWeekdays.contains(weekday)
    }

    var effectiveScheduledSummaryWeekdays: [Int] {
        return (1...7).filter { isScheduledSummaryActive(on: $0) }
    }

    var scheduledSummaryDaysSummaryText: String {
        let days = effectiveScheduledSummaryWeekdays
        if days.isEmpty { return "Nessun giorno" }
        if days == [1, 2, 3, 4, 5] { return "Lun - Ven" }
        if days == [1, 2, 3, 4, 5, 6, 7] { return "Tutti i giorni" }
        let labels = ["", "Lun", "Mar", "Mer", "Gio", "Ven", "Sab", "Dom"]
        return days.compactMap { (1...7).contains($0) ? labels[$0] : nil }.joined(separator: ", ")
    }

    // MARK: - Server Sync

    private static func cleanPreferredTrainNumbers(from trains: [CommuteHabitTrain]) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for tr in trains {
            let clean = StationNameMatcher.cleanTrainDigits(tr.trainNumber)
            if !clean.isEmpty && seen.insert(clean).inserted {
                result.append(clean)
            }
        }
        return result
    }

    private static func appendTrainPayloadFields(
        to dict: inout [String: Any],
        trains: [CommuteHabitTrain]
    ) {
        let numbers = cleanPreferredTrainNumbers(from: trains)
        guard !numbers.isEmpty else { return }
        dict["trains"] = numbers
        dict["train_details"] = trains.compactMap { tr -> [String: Any]? in
            let clean = StationNameMatcher.cleanTrainDigits(tr.trainNumber)
            guard !clean.isEmpty else { return nil }
            return [
                "number": clean,
                "category": tr.category,
                "origin": tr.originStation,
                "destination": tr.destinationStation,
                "departure_time": tr.departureTime,
                "arrival_time": tr.arrivalTime ?? "",
                "manual": tr.isManuallyAdded
            ]
        }
    }

    private func buildGroupedGlobalSchedules(
        type: String,
        band: String,
        scheduleOrigins: [String],
        scheduleDestinations: [String],
        sortedWeekdays: [Int],
        isReturn: Bool
    ) -> [[String: Any]] {
        var groups: [(signature: String, weekdays: [Int], trains: [CommuteHabitTrain])] = []
        for day in sortedWeekdays {
            let trains = effectiveTrains(for: day, isReturn: isReturn)
            let sig = Self.cleanPreferredTrainNumbers(from: trains).joined(separator: ",")
            if let idx = groups.firstIndex(where: { $0.signature == sig }) {
                groups[idx].weekdays.append(day)
            } else {
                groups.append((signature: sig, weekdays: [day], trains: trains))
            }
        }
        return groups.map { grp in
            var entry: [String: Any] = [
                "type": type,
                "time": band,
                "weekdays": grp.weekdays,
                "origins": scheduleOrigins,
                "destinations": scheduleDestinations
            ]
            Self.appendTrainPayloadFields(to: &entry, trains: grp.trains)
            return entry
        }
    }

    func buildCommuteSyncPayload() -> [String: Any]? {
        let supID = getSupporterEternalID()
        guard !supID.isEmpty else { return nil }
        guard !origins.isEmpty && !destinations.isEmpty else { return nil }

        let token = UserDefaults.standard.string(forKey: "apnsTokenKey_v1") ?? UserDefaults.standard.string(forKey: "deviceToken") ?? ""
        let model = UIDevice.current.model
        let supporterActive = hasSupport()
        let notificationsEnabled = UserDefaults.standard.object(forKey: "remoteNotificationsEnabled_v1") as? Bool ?? true

        var schedulesPayload: [[String: Any]] = []

        if customizePerDay {
            for day in 1...7 {
                if let config = daySchedules[day], config.isEnabled {
                    let outSt = Self.resolveEffectiveStations(
                        baseOrigins: origins,
                        baseDestinations: destinations,
                        schedule: config,
                        isReturn: false
                    )
                    let retSt = Self.resolveEffectiveStations(
                        baseOrigins: origins,
                        baseDestinations: destinations,
                        schedule: config,
                        isReturn: true
                    )
                    var outEntry: [String: Any] = [
                        "type": "outbound",
                        "time": config.outboundBand,
                        "weekdays": [day],
                        "origins": outSt.origins,
                        "destinations": outSt.destinations
                    ]
                    Self.appendTrainPayloadFields(to: &outEntry, trains: config.outboundTrains)
                    schedulesPayload.append(outEntry)

                    var retEntry: [String: Any] = [
                        "type": "return",
                        "time": config.returnBand,
                        "weekdays": [day],
                        "origins": retSt.origins,
                        "destinations": retSt.destinations
                    ]
                    Self.appendTrainPayloadFields(to: &retEntry, trains: config.returnTrains)
                    schedulesPayload.append(retEntry)
                }
            }
        } else {
            let sortedDays = activeWeekdays.sorted()
            schedulesPayload.append(contentsOf: buildGroupedGlobalSchedules(
                type: "outbound",
                band: defaultOutboundBand,
                scheduleOrigins: origins,
                scheduleDestinations: destinations,
                sortedWeekdays: sortedDays,
                isReturn: false
            ))
            schedulesPayload.append(contentsOf: buildGroupedGlobalSchedules(
                type: "return",
                band: defaultReturnBand,
                scheduleOrigins: destinations,
                scheduleDestinations: origins,
                sortedWeekdays: sortedDays,
                isReturn: true
            ))
        }

        return [
            "supporter_id": supID,
            "device_token": token,
            "device_id": DeviceIdentityManager.shared.deviceID,
            "platform": "ios",
            "device_model": model,
            "origins": origins,
            "destinations": destinations,
            "schedules": schedulesPayload,
            "proactive_alerts": supporterActive && notificationsEnabled && proactiveAlertsEnabled,
            "scheduled_summary_enabled": supporterActive && notificationsEnabled && scheduledSummaryEnabled,
            "scheduled_summary_mode": "always",
            "scheduled_summary_lead_minutes": scheduledSummaryLeadMinutes,
            "scheduled_summary_scope": scheduledSummaryScope,
            "scheduled_summary_weekdays": effectiveScheduledSummaryWeekdays,
            "has_support": supporterActive
        ]
    }

    func syncRoutineWithServer(allowRevocationWhenUnsupported: Bool = false) async {
        guard hasSupport() || allowRevocationWhenUnsupported else { return }
        guard let payload = buildCommuteSyncPayload() else { return }

        do {
            let res = try await NetworkService.shared.post(endpoint: "/supporter/commute", payload: payload)
            print("[+] Abitudini di viaggio sincronizzate con il server: \(res)")
            self.lastSyncError = nil
        } catch {
            print("[-] Errore sincronizzazione abitudini di viaggio: \(error.localizedDescription)")
            self.lastSyncError = error.localizedDescription
        }
    }

    // MARK: - Unified Casa <-> Lavoro Direction & Solutions Dispatcher (Free On-Device + Pro)

    nonisolated static func preferredIsReturn(
        at now: Date,
        outboundBand: String,
        returnBand: String
    ) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        let comps = cal.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)

        let outBand = CommuteTimeBand.parse(outboundBand, fallbackStart: 7 * 60, fallbackEnd: 8 * 60)
        let retBand = CommuteTimeBand.parse(returnBand, fallbackStart: 17 * 60, fallbackEnd: 18 * 60)
        let outEnd = (outBand.startMinutes + outBand.durationMinutes) % 1440
        let retStart = retBand.startMinutes

        if retStart > outEnd {
            let midpoint = (outEnd + retStart) / 2
            let cutoff = max(min(midpoint, retStart - 30), outEnd)
            return !(nowMinutes >= 180 && nowMinutes < cutoff)
        } else {
            let retLeadStart = max(0, retStart - 90)
            let outLeadStart = max(0, outBand.startMinutes - 90)
            return nowMinutes >= retLeadStart && nowMinutes < outLeadStart
        }
    }

    private func resolveManualDirectionOverride(dayKey: String, autoIsReturn: Bool) -> Bool? {
        let parts = manualDirectionOverrideRaw.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              parts[0] == dayKey,
              parts[1] == (autoIsReturn ? "R" : "O") else {
            return nil
        }
        return parts[2] == "1"
    }

    func currentCommuteRouteSlot(at now: Date = Date()) -> ActiveHabitCommuteSlot? {
        guard hasConfiguredCommute else { return nil }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        let weekday = ((cal.component(.weekday, from: now) + 5) % 7) + 1
        let bands = commuteBandsForDay(weekday)
        let autoReturn = Self.preferredIsReturn(at: now, outboundBand: bands.outbound, returnBand: bands.returnBand)
        let todayKey = Self.romeDayKey(for: now)
        let effectiveIsReturn = resolveManualDirectionOverride(dayKey: todayKey, autoIsReturn: autoReturn) ?? autoReturn

        let st = effectiveStations(for: weekday, isReturn: effectiveIsReturn)
        guard !st.origins.isEmpty && !st.destinations.isEmpty else { return nil }

        return ActiveHabitCommuteSlot(
            isReturn: effectiveIsReturn,
            origins: st.origins,
            destinations: st.destinations,
            timeBand: effectiveIsReturn ? bands.returnBand : bands.outbound
        )
    }

    func toggleCommuteRouteDirection(at now: Date = Date()) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        let weekday = ((cal.component(.weekday, from: now) + 5) % 7) + 1
        let bands = commuteBandsForDay(weekday)
        let autoReturn = Self.preferredIsReturn(at: now, outboundBand: bands.outbound, returnBand: bands.returnBand)
        let currentIsReturn = currentCommuteRouteSlot(at: now)?.isReturn ?? autoReturn
        let newIsReturn = !currentIsReturn
        manualDirectionOverrideRaw = "\(Self.romeDayKey(for: now))|\(autoReturn ? "R" : "O")|\(newIsReturn ? "1" : "0")"
        objectWillChange.send()
    }

    func fetchCommuteSolutionsReport(
        origins startStations: [String],
        destinations endStations: [String],
        departureDate: Date = Date(),
        isReturn: Bool,
        userLat: Double? = nil,
        userLon: Double? = nil,
        forceRefresh: Bool = false
    ) async -> PlanBReportDTO {
        isCalculatingCommuteSolutions = true
        defer { isCalculatingCommuteSolutions = false }

        let isNearNow = abs(departureDate.timeIntervalSinceNow) < 15 * 60
        if hasSupport() && isNearNow {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
            let bands = commuteBandsForDay(((cal.component(.weekday, from: departureDate) + 5) % 7) + 1)
            let timeBand = isReturn ? bands.returnBand : bands.outbound
            if let serverReport = try? await fetchPlanBReport(
                origins: startStations,
                destinations: endStations,
                timeBand: timeBand,
                isReturn: isReturn,
                userLat: userLat,
                userLon: userLon
            ), !serverReport.alternatives.isEmpty {
                return serverReport
            }
        }

        return await CommuteTrainDiscoveryService.shared.calculateLocalCommutePlan(
            origins: startStations,
            destinations: endStations,
            departureDate: departureDate,
            isReturn: isReturn,
            userLat: userLat,
            userLon: userLon,
            forceRefresh: forceRefresh
        )
    }
    
    // MARK: - Active Habit Commute Slot (Home "Per te")

    nonisolated static func parseTimeBandMinutes(_ band: String) -> (start: Int, end: Int)? {
        let parts = band.components(separatedBy: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return nil }
        func toMins(_ hhmm: String) -> Int? {
            let comps = hhmm.split(separator: ":")
            guard comps.count == 2, let h = Int(comps[0]), let m = Int(comps[1]),
                  (0...23).contains(h), (0...59).contains(m) else { return nil }
            return h * 60 + m
        }
        guard let start = toMins(parts[0]), var end = toMins(parts[1]) else { return nil }
        if end <= start { end += 24 * 60 } // es. "23:00 - 00:00"
        return (start, end)
    }

    nonisolated static func isMinute(_ nowMinutes: Int, withinBand band: String, leadMinutes: Int = 45, trailMinutes: Int = 30) -> Bool {
        guard let range = parseTimeBandMinutes(band) else { return false }
        let low = range.start - leadMinutes
        let high = range.end + trailMinutes
        return (nowMinutes >= low && nowMinutes <= high) ||
               (nowMinutes + 1440 >= low && nowMinutes + 1440 <= high)
    }

    func activeHabitCommuteSlot(at now: Date = Date(), leadMinutes: Int = 45, trailMinutes: Int = 30) -> ActiveHabitCommuteSlot? {
        guard hasSupport(), !origins.isEmpty, !destinations.isEmpty else { return nil }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        let weekday = ((cal.component(.weekday, from: now) + 5) % 7) + 1 // 1 = Lun ... 7 = Dom
        guard isCommuteDayActive(weekday) else { return nil }

        let comps = cal.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let bands = commuteBandsForDay(weekday)

        if Self.isMinute(nowMinutes, withinBand: bands.outbound, leadMinutes: leadMinutes, trailMinutes: trailMinutes) {
            let st = effectiveStations(for: weekday, isReturn: false)
            if !st.origins.isEmpty && !st.destinations.isEmpty {
                return ActiveHabitCommuteSlot(
                    isReturn: false,
                    origins: st.origins,
                    destinations: st.destinations,
                    timeBand: bands.outbound
                )
            }
        }

        if Self.isMinute(nowMinutes, withinBand: bands.returnBand, leadMinutes: leadMinutes, trailMinutes: trailMinutes) {
            let st = effectiveStations(for: weekday, isReturn: true)
            if !st.origins.isEmpty && !st.destinations.isEmpty {
                return ActiveHabitCommuteSlot(
                    isReturn: true,
                    origins: st.origins,
                    destinations: st.destinations,
                    timeBand: bands.returnBand
                )
            }
        }

        return nil
    }

    private func fetchPlanBReport(
        origins startStations: [String],
        destinations endStations: [String],
        timeBand: String,
        isReturn: Bool,
        userLat: Double?,
        userLon: Double?
    ) async throws -> PlanBReportDTO {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        let weekday = ((cal.component(.weekday, from: Date()) + 5) % 7) + 1

        var payload: [String: Any] = [
            "origins": startStations,
            "destinations": endStations,
            "time": timeBand,
            "incident_type": "simulation"
        ]
        let preferred = Self.cleanPreferredTrainNumbers(from: effectiveTrains(for: weekday, isReturn: isReturn))
        if !preferred.isEmpty {
            payload["preferred_trains"] = preferred
        }
        if let lat = userLat, let lon = userLon {
            payload["user_lat"] = lat
            payload["user_lon"] = lon
        }

        let data = try await NetworkService.shared.postData(endpoint: "/supporter/plan_b", payload: payload)
        return try JSONDecoder().decode(PlanBReportDTO.self, from: data)
    }

    // MARK: - Persistent Solution-Window Cache Helpers

    nonisolated static func romeDayKey(for date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    nonisolated static func effectiveDepartureMinutes(for alt: PlanBAlternativeItem) -> Int? {
        let rawTime = alt.resolvedLegs.first?.departure_time ?? alt.departure_time
        guard let base = CommuteTimeBand.parseHHmm(rawTime) else { return nil }
        return base + max(0, alt.delay)
    }

    /// Filtra localmente le soluzioni già ricevute dal server tenendo solo quelle non ancora partite
    /// (con margine di grazia di 2 min e supporto allo scavalco di mezzanotte).
    nonisolated static func upcomingAlternatives(
        in plan: PlanBReportDTO,
        at now: Date = Date(),
        graceMinutes: Int = 2
    ) -> [PlanBAlternativeItem] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        let comps = cal.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)

        return plan.alternatives.filter { alt in
            guard var dep = effectiveDepartureMinutes(for: alt) else { return true }
            if dep < 180 && nowMinutes > 1200 {
                dep += 1440
            }
            return dep >= (nowMinutes - graceMinutes)
        }
    }

    /// Restituisce `true` finché la cache è della giornata odierna e contiene ancora almeno una soluzione
    /// futura (fino all'orario dell'ultima partenza già scaricata dal server).
    nonisolated static func hasValidUpcomingCachedSolutions(
        plan: PlanBReportDTO,
        dayKey: String,
        at now: Date = Date(),
        graceMinutes: Int = 2
    ) -> Bool {
        guard dayKey == romeDayKey(for: now) else { return false }
        return !upcomingAlternatives(in: plan, at: now, graceMinutes: graceMinutes).isEmpty
    }

    func hasValidCachedProactiveHabitPlan(for slotKey: String, at now: Date = Date()) -> Bool {
        guard cachedProactiveHabitSlotKey == slotKey,
              let cached = cachedProactiveHabitPlan else {
            return false
        }
        return Self.hasValidUpcomingCachedSolutions(plan: cached, dayKey: cachedProactiveHabitDayKey, at: now)
    }

    private func persistProactiveHabitCache(plan: PlanBReportDTO, slotKey: String, dayKey: String, fetchedAt: Date) {
        let entry = CachedProactiveHabitPlan(
            slotKey: slotKey,
            dayKey: dayKey,
            fetchedAt: fetchedAt,
            plan: plan
        )
        if let data = try? JSONEncoder().encode(entry),
           let json = String(data: data, encoding: .utf8) {
            proactiveHabitCacheJSON = json
        }
    }

    /// Carica in modo proattivo le soluzioni per la fascia oraria abituale e le salva in cache persistente:
    /// finché esistono soluzioni non ancora partite fino all'ultima partenza ricevuta, l'app mostra localmente
    /// le soluzioni successive senza richiamare il server (salvo pull-to-refresh manuale `force: true`).
    func loadProactiveHabitPlanIfNeeded(
        for slot: ActiveHabitCommuteSlot,
        slotKey: String,
        userLat: Double? = nil,
        userLon: Double? = nil,
        force: Bool = false
    ) async -> PlanBReportDTO? {
        let now = Date()
        if !force && hasValidCachedProactiveHabitPlan(for: slotKey, at: now) {
            return cachedProactiveHabitPlan
        }
        if cachedProactiveHabitSlotKey != slotKey {
            cachedProactiveHabitPlan = nil
            cachedProactiveHabitSlotKey = slotKey
            cachedProactiveHabitDayKey = ""
            cachedProactiveHabitFetchedAt = nil
        }
        guard let report = await fetchProactiveHabitPlan(for: slot, userLat: userLat, userLon: userLon) else {
            return cachedProactiveHabitPlan
        }
        let todayKey = Self.romeDayKey(for: now)
        cachedProactiveHabitPlan = report
        cachedProactiveHabitSlotKey = slotKey
        cachedProactiveHabitDayKey = todayKey
        cachedProactiveHabitFetchedAt = now
        persistProactiveHabitCache(plan: report, slotKey: slotKey, dayKey: todayKey, fetchedAt: now)
        return report
    }

    /// Carica in modo proattivo le soluzioni per la fascia oraria abituale senza alterare `activePlanB` globale.
    func fetchProactiveHabitPlan(
        for slot: ActiveHabitCommuteSlot,
        userLat: Double? = nil,
        userLon: Double? = nil
    ) async -> PlanBReportDTO? {
        guard hasSupport(), !slot.origins.isEmpty, !slot.destinations.isEmpty else { return nil }
        do {
            let report = try await fetchPlanBReport(
                origins: slot.origins,
                destinations: slot.destinations,
                timeBand: slot.timeBand,
                isReturn: slot.isReturn,
                userLat: userLat,
                userLon: userLon
            )
            self.lastSyncError = nil
            return report
        } catch {
            print("[-] Errore fetch proattivo viaggio abituale: \(error.localizedDescription)")
            return nil
        }
    }

    func requestHabitTripPlan(for slot: ActiveHabitCommuteSlot, userLat: Double? = nil, userLon: Double? = nil) async {
        await requestManualPlanB(
            origins: slot.origins,
            destinations: slot.destinations,
            for: slot.isReturn,
            timeBandOverride: slot.timeBand,
            overrideAreStationsFinal: true,
            userLat: userLat,
            userLon: userLon
        )
    }

    func requestManualPlanB(origins customOrigins: [String]? = nil, destinations customDestinations: [String]? = nil, for returnTrip: Bool = false, timeBandOverride: String? = nil, overrideAreStationsFinal: Bool = false, userLat: Double? = nil, userLon: Double? = nil) async {
        guard hasSupport() else { return }
        isCalculatingPlanB = true
        chosenAlternativeId = nil
        defer { isCalculatingPlanB = false }
        
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        let weekday = ((cal.component(.weekday, from: Date()) + 5) % 7) + 1
        
        let startStations: [String]
        let endStations: [String]
        if let cOrig = customOrigins, let cDest = customDestinations {
            startStations = (returnTrip && !overrideAreStationsFinal) ? cDest : cOrig
            endStations = (returnTrip && !overrideAreStationsFinal) ? cOrig : cDest
        } else {
            let resolved = effectiveStations(for: weekday, isReturn: returnTrip)
            startStations = resolved.origins
            endStations = resolved.destinations
        }
        
        let targetBand: String = {
            if let override = timeBandOverride, !override.isEmpty {
                return override
            }
            if customizePerDay, let sched = daySchedules[weekday] {
                return returnTrip ? sched.returnBand : sched.outboundBand
            }
            return returnTrip ? defaultReturnBand : defaultOutboundBand
        }()
        
        guard !startStations.isEmpty && !endStations.isEmpty else { return }
        
        do {
            let report = try await fetchPlanBReport(
                origins: startStations,
                destinations: endStations,
                timeBand: targetBand,
                isReturn: returnTrip,
                userLat: userLat,
                userLon: userLon
            )
            self.activePlanB = report
            self.lastSyncError = nil
        } catch {
            print("[-] Errore richiesta manuale alternative: \(error.localizedDescription)")
            self.lastSyncError = error.localizedDescription
            self.activePlanB = nil
        }
    }
}
