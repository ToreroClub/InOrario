import Foundation
import SwiftUI
import CoreLocation
import UIKit

// MARK: - Persistent Local Telemetry Models

struct TelemetryStationEntry: Codable, Sendable {
    var name: String
    var vtID: String?
    var rfiID: String?
    var viewCount: Int
    var searchCount: Int
    var firstSeen: String
    var lastSeen: String
    var daysSeen: [String]
    var hoursHistogram: [String: Int]
    var weekdaysHistogram: [String: Int]
    var gpsConfirmedCount: Int
    var lastLat: Double?
    var lastLon: Double?

    enum CodingKeys: String, CodingKey {
        case name
        case vtID = "vt_id"
        case rfiID = "rfi_id"
        case viewCount = "view_count"
        case searchCount = "search_count"
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
        case daysSeen = "days_seen"
        case hoursHistogram = "hours_histogram"
        case weekdaysHistogram = "weekdays_histogram"
        case gpsConfirmedCount = "gps_confirmed_count"
        case lastLat = "last_lat"
        case lastLon = "last_lon"
    }
}

struct TelemetryTrainEntry: Codable, Sendable {
    var number: String
    var category: String
    var destination: String
    var origin: String?
    var departureTime: String?
    var viewCount: Int
    var searchCount: Int
    var firstSeen: String
    var lastSeen: String
    var daysSeen: [String]
    var hoursHistogram: [String: Int]
    var weekdaysHistogram: [String: Int]

    enum CodingKeys: String, CodingKey {
        case number, category, destination, origin
        case departureTime = "departure_time"
        case viewCount = "view_count"
        case searchCount = "search_count"
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
        case daysSeen = "days_seen"
        case hoursHistogram = "hours_histogram"
        case weekdaysHistogram = "weekdays_histogram"
    }
}

struct TelemetryRouteEntry: Codable, Sendable {
    var originName: String
    var originID: String
    var destinationName: String
    var destinationID: String
    var viewCount: Int
    var firstSeen: String
    var lastSeen: String
    var daysSeen: [String]
    var hoursHistogram: [String: Int]
    var weekdaysHistogram: [String: Int]

    enum CodingKeys: String, CodingKey {
        case originName = "origin_name"
        case originID = "origin_id"
        case destinationName = "destination_name"
        case destinationID = "destination_id"
        case viewCount = "view_count"
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
        case daysSeen = "days_seen"
        case hoursHistogram = "hours_histogram"
        case weekdaysHistogram = "weekdays_histogram"
    }
}

struct TelemetrySearchEntry: Codable, Sendable {
    var type: String // "station", "train", "route", "assistant", "metro"
    var query: String
    var count: Int
    var firstSeen: String
    var lastSeen: String
    var origin: String?
    var destination: String?

    enum CodingKeys: String, CodingKey {
        case type, query, count, origin, destination
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
    }
}

struct TelemetrySearchEvent: Codable, Sendable {
    var type: String
    var query: String
    var timestamp: String
    var origin: String?
    var destination: String?
}

struct TelemetryViewedTripEntry: Codable, Sendable {
    var tripID: String
    var origin: String
    var destination: String
    var departureTime: String
    var arrivalTime: String
    var duration: String
    var trains: [String]
    var viewCount: Int
    var firstSeen: String
    var lastSeen: String

    enum CodingKeys: String, CodingKey {
        case tripID = "trip_id"
        case origin, destination, duration, trains
        case departureTime = "departure_time"
        case arrivalTime = "arrival_time"
        case viewCount = "view_count"
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
    }
}

struct TelemetryLineEntry: Codable, Sendable, Equatable {
    var lineID: String
    var code: String
    var name: String
    var kind: String
    var region: String
    var viewCount: Int
    var firstSeen: String
    var lastSeen: String
    var daysSeen: [String]
    var hoursHistogram: [String: Int]
    var weekdaysHistogram: [String: Int]

    enum CodingKeys: String, CodingKey {
        case lineID = "line_id"
        case code, name, kind, region
        case viewCount = "view_count"
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
        case daysSeen = "days_seen"
        case hoursHistogram = "hours_histogram"
        case weekdaysHistogram = "weekdays_histogram"
    }
}

struct TelemetryInfomobilityEntry: Codable, Sendable {
    var key: String
    var title: String
    var category: String
    var regions: [String]
    var company: String?
    var service: String?
    var viewCount: Int
    var firstSeen: String
    var lastSeen: String

    enum CodingKeys: String, CodingKey {
        case key, title, category, regions, company, service
        case viewCount = "view_count"
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
    }
}

struct TelemetryLocalStore: Codable, Sendable {
    var stationHistory: [String: TelemetryStationEntry] = [:]
    var trainHistory: [String: TelemetryTrainEntry] = [:]
    var lineHistory: [String: TelemetryLineEntry] = [:]
    var routeHistory: [String: TelemetryRouteEntry] = [:]
    var searches: [String: TelemetrySearchEntry] = [:]
    var recentSearchEvents: [TelemetrySearchEvent] = []
    var viewedTripsHistory: [String: TelemetryViewedTripEntry] = [:]
    var infomobilityViews: [String: TelemetryInfomobilityEntry] = [:]
    var pendingBatchID: String? = nil
    var oldestPendingDay: String? = nil

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stationHistory = try c.decodeIfPresent([String: TelemetryStationEntry].self, forKey: .stationHistory) ?? [:]
        trainHistory = try c.decodeIfPresent([String: TelemetryTrainEntry].self, forKey: .trainHistory) ?? [:]
        lineHistory = try c.decodeIfPresent([String: TelemetryLineEntry].self, forKey: .lineHistory) ?? [:]
        routeHistory = try c.decodeIfPresent([String: TelemetryRouteEntry].self, forKey: .routeHistory) ?? [:]
        searches = try c.decodeIfPresent([String: TelemetrySearchEntry].self, forKey: .searches) ?? [:]
        recentSearchEvents = try c.decodeIfPresent([TelemetrySearchEvent].self, forKey: .recentSearchEvents) ?? []
        viewedTripsHistory = try c.decodeIfPresent([String: TelemetryViewedTripEntry].self, forKey: .viewedTripsHistory) ?? [:]
        infomobilityViews = try c.decodeIfPresent([String: TelemetryInfomobilityEntry].self, forKey: .infomobilityViews) ?? [:]
        pendingBatchID = try c.decodeIfPresent(String.self, forKey: .pendingBatchID)
        oldestPendingDay = try c.decodeIfPresent(String.self, forKey: .oldestPendingDay)
    }

    var isEmpty: Bool {
        stationHistory.isEmpty &&
        trainHistory.isEmpty &&
        lineHistory.isEmpty &&
        routeHistory.isEmpty &&
        searches.isEmpty &&
        recentSearchEvents.isEmpty &&
        viewedTripsHistory.isEmpty &&
        infomobilityViews.isEmpty
    }
}

private struct TelemetryFavoriteLineDTO: Encodable {
    let line_id: String
    let code: String
    let name: String
    let kind: String
    let region: String
}

private struct TelemetrySyncAckResponse: Decodable {
    let status: String?
    let saved: Bool?
    let user_id: String?
    let batch_id: String?
}

// MARK: - Outbound Sync Payload DTOs

private struct TelemetryFavoriteStationDTO: Encodable {
    let name: String
    let vt_id: String?
    let rfi_id: String?
    let lat: Double?
    let lon: Double?
    let added_date: String?
}

private struct TelemetryFavoriteTrainDTO: Encodable {
    let number: String
    let category: String
    let description: String
    let origin: String?
    let destination: String
    let departure_time: String?
    let arrival_time: String?
    let active_days: [Int]?
    let notify_delay: Bool
    let notify_departure: Bool
    let notify_station_pass: Bool
    let station_pass_name: String?
    let notify_platform_change: Bool
    let added_date: String?
}

private struct TelemetryFavoriteRouteDTO: Encodable {
    let origin_name: String
    let origin_id: String
    let destination_name: String
    let destination_id: String
    let last_viewed_at: String?
}

private struct TelemetrySmartRouteDTO: Encodable {
    let origin_name: String
    let destination_name: String
}

private struct TelemetrySavedTripSegmentDTO: Encodable {
    let origin: String
    let destination: String
    let departure_time: String
    let arrival_time: String
    let train_number: String
    let train_category: String
}

private struct TelemetrySavedTripDTO: Encodable {
    let id: String
    let origin: String
    let destination: String
    let departure_time: String
    let arrival_time: String
    let duration: String
    let segments: [TelemetrySavedTripSegmentDTO]
    let last_viewed_at: String?
}

private struct TelemetryCommuteRoutineDTO: Encodable {
    let origins: [String]
    let destinations: [String]
    let default_outbound_band: String
    let default_return_band: String
    let active_weekdays: [Int]
    let proactive_alerts_enabled: Bool
    let scheduled_summary_enabled: Bool
    let habit_trains: [String]
}

private struct TelemetryLearnedHabitSlotDTO: Encodable {
    let slot: String
    let time_range: String
    let stations: [TelemetryLearnedStationDTO]
    let trains: [TelemetryLearnedTrainDTO]
}

private struct TelemetryLearnedStationDTO: Encodable {
    let name: String
    let total_views: Int
    let distinct_days: Int
    let is_favorite: Bool
    let strength: String
}

private struct TelemetryLearnedTrainDTO: Encodable {
    let number: String
    let category: String
    let destination: String
    let departure_time: String?
    let total_views: Int
    let distinct_days: Int
    let is_favorite: Bool
    let strength: String
}

private struct TelemetrySyncPayload: Encodable {
    let device_id: String
    let apns_token: String?
    let platform: String
    let device_model: String
    let os_version: String
    let app_version: String
    let locale: String
    let has_support: Bool
    let strike_region: String
    let strike_notifications_enabled: Bool
    let remote_notifications_enabled: Bool
    let sync_day: String
    let generated_at: String
    let previous_sync_at: String?
    let payload_mode: String
    let batch_id: String

    let favorite_stations: [TelemetryFavoriteStationDTO]
    let favorite_trains: [TelemetryFavoriteTrainDTO]
    let favorite_lines: [TelemetryFavoriteLineDTO]
    let favorite_routes: [TelemetryFavoriteRouteDTO]
    let smart_routes: [TelemetrySmartRouteDTO]
    let saved_trips: [TelemetrySavedTripDTO]
    let commute_routine: TelemetryCommuteRoutineDTO?
    let learned_habits: [TelemetryLearnedHabitSlotDTO]

    let station_history: [TelemetryStationEntry]
    let train_history: [TelemetryTrainEntry]
    let line_history: [TelemetryLineEntry]
    let route_history: [TelemetryRouteEntry]
    let searches: [TelemetrySearchEntry]
    let recent_search_events: [TelemetrySearchEvent]
    let viewed_trips_history: [TelemetryViewedTripEntry]
    let infomobility_views: [TelemetryInfomobilityEntry]
}

// MARK: - UserInterestTelemetryManager

/// Raccoglie localmente tutta l'attività dell'utente (stazioni, treni, tratte, ricerche, viaggi,
/// preferiti, routine pendolare, visualizzazioni infomobilità/lavori/scioperi) con contatori di
/// visualizzazione persistenti e invia un aggiornamento completo al server una volta al giorno
/// alla prima apertura dell'app della giornata (ritentando automaticamente se offline/fallito).
@MainActor
final class UserInterestTelemetryManager {
    static let shared = UserInterestTelemetryManager()

    private let syncURLString = "https://gestioneinorario.toreroclub.com/user/telemetry/sync"
    private let lastSyncDayKey = "user_telemetry_last_sync_day_v1"
    private let lastSyncAtKey = "user_telemetry_last_sync_at_v1"
    private let bootstrappedKey = "user_telemetry_bootstrapped_v1"

    private let ioQueue = DispatchQueue(label: "com.toreroclub.inorario.user_telemetry.io", qos: .utility)
    private var store = TelemetryLocalStore()
    private var isSyncing = false
    private var lastSyncAttemptAt: Date? = nil
    private var pendingSaveWorkItem: DispatchWorkItem? = nil

    private let maxDaysStoredPerItem = 90
    private let maxRecentSearchEvents = 120
    private let maxDictionaryItems = 350

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private init() {
        loadStoreFromDisk()
    }

    // MARK: - Opt-In / Opt-Out ("Suggerimenti personalizzati")

    /// Rispetta l'interruttore "Suggerimenti personalizzati" in Impostazioni.
    /// Quando disattivato, l'app interrompe raccolta e invio telemetria anonima.
    var isCollectionEnabled: Bool {
        if UserDefaults.standard.object(forKey: "smartSuggestionsEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "smartSuggestionsEnabled")
    }

    var hasPendingUnsentData: Bool {
        !store.isEmpty
    }

    func clearLocalStore() {
        pendingSaveWorkItem?.cancel()
        store = TelemetryLocalStore()
        let url = storeFileURL
        ioQueue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func markPendingDayIfNeeded(_ day: String) {
        if store.oldestPendingDay == nil {
            store.oldestPendingDay = day
        } else if let current = store.oldestPendingDay, day < current {
            store.oldestPendingDay = day
        }
        if store.pendingBatchID == nil || store.pendingBatchID?.isEmpty == true {
            store.pendingBatchID = UUID().uuidString.lowercased()
        }
    }

    // MARK: - Persistence

    private var storeFileURL: URL {
        let fm = FileManager.default
        let appSupport = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        return appSupport.appendingPathComponent("user_interest_telemetry_v1.json")
    }

    private func loadStoreFromDisk() {
        let url = storeFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(TelemetryLocalStore.self, from: data)
            self.store = decoded
        } catch {
            print("[UserTelemetry] Errore lettura store locale: \(error.localizedDescription)")
        }
    }

    private func scheduleSave() {
        pendingSaveWorkItem?.cancel()
        let snapshot = store
        let url = storeFileURL
        let work = DispatchWorkItem { [ioQueue] in
            ioQueue.async {
                do {
                    let data = try JSONEncoder().encode(snapshot)
                    try data.write(to: url, options: [.atomic])
                } catch {
                    print("[UserTelemetry] Errore salvataggio store locale: \(error.localizedDescription)")
                }
            }
        }
        pendingSaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    func flushToDiskNow() {
        pendingSaveWorkItem?.cancel()
        let snapshot = store
        let url = storeFileURL
        ioQueue.async {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: [.atomic])
            } catch {
                print("[UserTelemetry] Errore flush store locale: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Helpers

    private func normalizeKey(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func appendUniqueDay(_ day: String, to days: inout [String]) {
        if !days.contains(day) {
            days.append(day)
            if days.count > maxDaysStoredPerItem {
                days.removeFirst(days.count - maxDaysStoredPerItem)
            }
        }
    }

    private func pruneDictionaryIfNeeded<T>(_ dict: inout [String: T], lastSeen: (T) -> String) {
        guard dict.count > maxDictionaryItems else { return }
        let sortedKeys = dict.sorted { lastSeen($0.value) > lastSeen($1.value) }
            .prefix(maxDictionaryItems)
            .map(\.key)
        let keep = Set(sortedKeys)
        dict = dict.filter { keep.contains($0.key) }
    }

    private func currentDeviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        return machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
    }

    // MARK: - Event Recording APIs

    func recordStationView(
        name: String,
        vtID: String? = nil,
        rfiID: String? = nil,
        gpsNear: Bool = false,
        location: CLLocationCoordinate2D? = nil,
        isFromSearch: Bool = false,
        at date: Date = Date()
    ) {
        guard isCollectionEnabled else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        let key = normalizeKey(cleanName)
        let iso = isoFormatter.string(from: date)
        let day = dayFormatter.string(from: date)
        markPendingDayIfNeeded(day)
        let cal = Calendar.current
        let hourKey = String(cal.component(.hour, from: date))
        let weekdayKey = String(cal.component(.weekday, from: date))

        if var entry = store.stationHistory[key] {
            entry.viewCount += 1
            if isFromSearch { entry.searchCount += 1 }
            if entry.vtID == nil, let vt = vtID, !vt.isEmpty { entry.vtID = vt }
            if entry.rfiID == nil, let rfi = rfiID, !rfi.isEmpty { entry.rfiID = rfi }
            if iso > entry.lastSeen { entry.lastSeen = iso }
            if iso < entry.firstSeen { entry.firstSeen = iso }
            appendUniqueDay(day, to: &entry.daysSeen)
            entry.hoursHistogram[hourKey, default: 0] += 1
            entry.weekdaysHistogram[weekdayKey, default: 0] += 1
            if gpsNear { entry.gpsConfirmedCount += 1 }
            if let loc = location {
                entry.lastLat = loc.latitude
                entry.lastLon = loc.longitude
            }
            store.stationHistory[key] = entry
        } else {
            store.stationHistory[key] = TelemetryStationEntry(
                name: cleanName,
                vtID: (vtID?.isEmpty == false) ? vtID : nil,
                rfiID: (rfiID?.isEmpty == false) ? rfiID : nil,
                viewCount: 1,
                searchCount: isFromSearch ? 1 : 0,
                firstSeen: iso,
                lastSeen: iso,
                daysSeen: [day],
                hoursHistogram: [hourKey: 1],
                weekdaysHistogram: [weekdayKey: 1],
                gpsConfirmedCount: gpsNear ? 1 : 0,
                lastLat: location?.latitude,
                lastLon: location?.longitude
            )
            pruneDictionaryIfNeeded(&store.stationHistory, lastSeen: \.lastSeen)
        }
        scheduleSave()
    }

    func recordTrainView(
        number: String,
        category: String? = nil,
        destination: String? = nil,
        origin: String? = nil,
        departureTime: String? = nil,
        isFromSearch: Bool = false,
        at date: Date = Date()
    ) {
        guard isCollectionEnabled else { return }
        let cleanNum = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanNum.isEmpty else { return }
        let iso = isoFormatter.string(from: date)
        let day = dayFormatter.string(from: date)
        markPendingDayIfNeeded(day)
        let cal = Calendar.current
        let hourKey = String(cal.component(.hour, from: date))
        let weekdayKey = String(cal.component(.weekday, from: date))
        let resolvedCat = resolveTrainCategory(number: cleanNum, categoryDesc: category, destination: destination)
        let cleanDest = (destination ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanOrigin = origin?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDep = (departureTime != nil && departureTime != "--:--" && !(departureTime?.isEmpty ?? true)) ? departureTime : nil

        if var entry = store.trainHistory[cleanNum] {
            entry.viewCount += 1
            if isFromSearch { entry.searchCount += 1 }
            if !resolvedCat.isEmpty && (entry.category.isEmpty || entry.category == "REG" || entry.category == "Treno") {
                entry.category = resolvedCat
            }
            if !cleanDest.isEmpty && cleanDest != "Caricamento..." && cleanDest != "Destinazione" {
                entry.destination = cleanDest
            }
            if let o = cleanOrigin, !o.isEmpty {
                entry.origin = o
            }
            if let dep = cleanDep {
                entry.departureTime = dep
            }
            if iso > entry.lastSeen { entry.lastSeen = iso }
            if iso < entry.firstSeen { entry.firstSeen = iso }
            appendUniqueDay(day, to: &entry.daysSeen)
            entry.hoursHistogram[hourKey, default: 0] += 1
            entry.weekdaysHistogram[weekdayKey, default: 0] += 1
            store.trainHistory[cleanNum] = entry
        } else {
            store.trainHistory[cleanNum] = TelemetryTrainEntry(
                number: cleanNum,
                category: resolvedCat,
                destination: (cleanDest == "Caricamento..." || cleanDest == "Destinazione") ? "" : cleanDest,
                origin: (cleanOrigin?.isEmpty == false) ? cleanOrigin : nil,
                departureTime: cleanDep,
                viewCount: 1,
                searchCount: isFromSearch ? 1 : 0,
                firstSeen: iso,
                lastSeen: iso,
                daysSeen: [day],
                hoursHistogram: [hourKey: 1],
                weekdaysHistogram: [weekdayKey: 1]
            )
            pruneDictionaryIfNeeded(&store.trainHistory, lastSeen: \.lastSeen)
        }
        scheduleSave()
    }

    func recordLineView(
        lineID: String,
        code: String,
        name: String,
        kind: String,
        region: String,
        at date: Date = Date()
    ) {
        guard isCollectionEnabled else { return }
        let cleanID = lineID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = normalizeKey(cleanID.isEmpty ? (cleanCode.isEmpty ? cleanName : cleanCode) : cleanID)
        guard !key.isEmpty else { return }

        let iso = isoFormatter.string(from: date)
        let day = dayFormatter.string(from: date)
        markPendingDayIfNeeded(day)
        let cal = Calendar.current
        let hourKey = String(cal.component(.hour, from: date))
        let weekdayKey = String(cal.component(.weekday, from: date))

        if var entry = store.lineHistory[key] {
            entry.viewCount += 1
            if !cleanCode.isEmpty { entry.code = cleanCode }
            if !cleanName.isEmpty { entry.name = cleanName }
            if !kind.isEmpty { entry.kind = kind }
            if !region.isEmpty { entry.region = region }
            if iso > entry.lastSeen { entry.lastSeen = iso }
            if iso < entry.firstSeen { entry.firstSeen = iso }
            appendUniqueDay(day, to: &entry.daysSeen)
            entry.hoursHistogram[hourKey, default: 0] += 1
            entry.weekdaysHistogram[weekdayKey, default: 0] += 1
            store.lineHistory[key] = entry
        } else {
            store.lineHistory[key] = TelemetryLineEntry(
                lineID: cleanID.isEmpty ? key : cleanID,
                code: cleanCode,
                name: cleanName.isEmpty ? cleanCode : cleanName,
                kind: kind,
                region: region,
                viewCount: 1,
                firstSeen: iso,
                lastSeen: iso,
                daysSeen: [day],
                hoursHistogram: [hourKey: 1],
                weekdaysHistogram: [weekdayKey: 1]
            )
            pruneDictionaryIfNeeded(&store.lineHistory, lastSeen: \.lastSeen)
        }
        scheduleSave()
    }

    func recordRouteUsage(
        originName: String,
        originID: String,
        destinationName: String,
        destinationID: String,
        at date: Date = Date()
    ) {
        guard isCollectionEnabled else { return }
        let cleanOrig = originName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDest = destinationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanOrig.isEmpty, !cleanDest.isEmpty else { return }

        let key = "\(normalizeKey(cleanOrig))->\(normalizeKey(cleanDest))"
        let iso = isoFormatter.string(from: date)
        let day = dayFormatter.string(from: date)
        markPendingDayIfNeeded(day)
        let cal = Calendar.current
        let hourKey = String(cal.component(.hour, from: date))
        let weekdayKey = String(cal.component(.weekday, from: date))

        if var entry = store.routeHistory[key] {
            entry.viewCount += 1
            if entry.originID.isEmpty, !originID.isEmpty { entry.originID = originID }
            if entry.destinationID.isEmpty, !destinationID.isEmpty { entry.destinationID = destinationID }
            if iso > entry.lastSeen { entry.lastSeen = iso }
            if iso < entry.firstSeen { entry.firstSeen = iso }
            appendUniqueDay(day, to: &entry.daysSeen)
            entry.hoursHistogram[hourKey, default: 0] += 1
            entry.weekdaysHistogram[weekdayKey, default: 0] += 1
            store.routeHistory[key] = entry
        } else {
            store.routeHistory[key] = TelemetryRouteEntry(
                originName: cleanOrig,
                originID: originID,
                destinationName: cleanDest,
                destinationID: destinationID,
                viewCount: 1,
                firstSeen: iso,
                lastSeen: iso,
                daysSeen: [day],
                hoursHistogram: [hourKey: 1],
                weekdaysHistogram: [weekdayKey: 1]
            )
            pruneDictionaryIfNeeded(&store.routeHistory, lastSeen: \.lastSeen)
        }

        recordSearch(type: "route", query: "\(cleanOrig) → \(cleanDest)", origin: cleanOrig, destination: cleanDest, at: date)
    }

    func recordSearch(
        type: String,
        query: String,
        origin: String? = nil,
        destination: String? = nil,
        at date: Date = Date()
    ) {
        guard isCollectionEnabled else { return }
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return }
        let key = "\(type)|\(normalizeKey(cleanQuery))"
        let iso = isoFormatter.string(from: date)
        markPendingDayIfNeeded(dayFormatter.string(from: date))

        if var entry = store.searches[key] {
            entry.count += 1
            if iso > entry.lastSeen { entry.lastSeen = iso }
            if iso < entry.firstSeen { entry.firstSeen = iso }
            if let o = origin, !o.isEmpty { entry.origin = o }
            if let d = destination, !d.isEmpty { entry.destination = d }
            store.searches[key] = entry
        } else {
            store.searches[key] = TelemetrySearchEntry(
                type: type,
                query: cleanQuery,
                count: 1,
                firstSeen: iso,
                lastSeen: iso,
                origin: origin,
                destination: destination
            )
            pruneDictionaryIfNeeded(&store.searches, lastSeen: \.lastSeen)
        }

        // Evita duplicati ravvicinati nello stream recente
        if let first = store.recentSearchEvents.first,
           first.type == type,
           first.query.caseInsensitiveCompare(cleanQuery) == .orderedSame,
           let prevDate = isoFormatter.date(from: first.timestamp),
           abs(date.timeIntervalSince(prevDate)) < 30 {
            scheduleSave()
            return
        }

        store.recentSearchEvents.insert(
            TelemetrySearchEvent(
                type: type,
                query: cleanQuery,
                timestamp: iso,
                origin: origin,
                destination: destination
            ),
            at: 0
        )
        if store.recentSearchEvents.count > maxRecentSearchEvents {
            store.recentSearchEvents = Array(store.recentSearchEvents.prefix(maxRecentSearchEvents))
        }
        scheduleSave()
    }

    func recordViewedTrip(_ trip: SavedTrip, at date: Date = Date()) {
        guard isCollectionEnabled else { return }
        let cleanOrig = trip.origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDest = trip.destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanOrig.isEmpty, !cleanDest.isEmpty else { return }
        let iso = isoFormatter.string(from: date)
        markPendingDayIfNeeded(dayFormatter.string(from: date))
        let trainCodes = trip.segments.compactMap { seg -> String? in
            let n = seg.trainNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !n.isEmpty else { return nil }
            let cat = seg.trainCategory.trimmingCharacters(in: .whitespacesAndNewlines)
            return cat.isEmpty ? n : "\(cat) \(n)"
        }

        if var entry = store.viewedTripsHistory[trip.id] {
            entry.viewCount += 1
            if iso > entry.lastSeen { entry.lastSeen = iso }
            if iso < entry.firstSeen { entry.firstSeen = iso }
            store.viewedTripsHistory[trip.id] = entry
        } else {
            store.viewedTripsHistory[trip.id] = TelemetryViewedTripEntry(
                tripID: trip.id,
                origin: cleanOrig,
                destination: cleanDest,
                departureTime: trip.departureTime,
                arrivalTime: trip.arrivalTime,
                duration: trip.duration,
                trains: trainCodes,
                viewCount: 1,
                firstSeen: iso,
                lastSeen: iso
            )
            pruneDictionaryIfNeeded(&store.viewedTripsHistory, lastSeen: \.lastSeen)
        }
        scheduleSave()
    }

    func recordInfomobilityView(item: NewsItem, at date: Date = Date()) {
        guard isCollectionEnabled else { return }
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let key = item.guid ?? normalizeKey(title)
        let iso = isoFormatter.string(from: date)
        markPendingDayIfNeeded(dayFormatter.string(from: date))
        let category = item.category ?? (item.isUrgent ? "urgente" : "infomobilita")
        let regions = item.regions ?? []

        if var entry = store.infomobilityViews[key] {
            entry.viewCount += 1
            if iso > entry.lastSeen { entry.lastSeen = iso }
            if iso < entry.firstSeen { entry.firstSeen = iso }
            store.infomobilityViews[key] = entry
        } else {
            store.infomobilityViews[key] = TelemetryInfomobilityEntry(
                key: key,
                title: title,
                category: category,
                regions: regions,
                company: item.meta?.company,
                service: item.meta?.service,
                viewCount: 1,
                firstSeen: iso,
                lastSeen: iso
            )
            pruneDictionaryIfNeeded(&store.infomobilityViews, lastSeen: \.lastSeen)
        }
        scheduleSave()
    }

    // MARK: - Bootstrap Legacy Data (once)

    private func bootstrapFromExistingHistoryIfNeeded(manager: TrainManager, usageTracker: UsageTracker) {
        guard !UserDefaults.standard.bool(forKey: bootstrappedKey) else { return }

        for visit in usageTracker.stationVisits {
            let count = max(1, visit.viewCount ?? 1)
            let key = normalizeKey(visit.stationName)
            let iso = isoFormatter.string(from: visit.date)
            let day = dayFormatter.string(from: visit.date)
            markPendingDayIfNeeded(day)
            let hourKey = String(visit.hour)
            let weekdayKey = String(visit.weekday)

            if var entry = store.stationHistory[key] {
                entry.viewCount += count
                if entry.vtID == nil { entry.vtID = visit.vtID }
                if entry.rfiID == nil { entry.rfiID = visit.rfiID }
                if iso > entry.lastSeen { entry.lastSeen = iso }
                if iso < entry.firstSeen { entry.firstSeen = iso }
                appendUniqueDay(day, to: &entry.daysSeen)
                entry.hoursHistogram[hourKey, default: 0] += count
                entry.weekdaysHistogram[weekdayKey, default: 0] += count
                if visit.gpsConfirmed { entry.gpsConfirmedCount += 1 }
                store.stationHistory[key] = entry
            } else {
                store.stationHistory[key] = TelemetryStationEntry(
                    name: visit.stationName,
                    vtID: visit.vtID,
                    rfiID: visit.rfiID,
                    viewCount: count,
                    searchCount: 0,
                    firstSeen: iso,
                    lastSeen: iso,
                    daysSeen: [day],
                    hoursHistogram: [hourKey: count],
                    weekdaysHistogram: [weekdayKey: count],
                    gpsConfirmedCount: visit.gpsConfirmed ? 1 : 0,
                    lastLat: visit.lat,
                    lastLon: visit.lon
                )
            }
        }

        for check in usageTracker.trainChecks {
            let count = max(1, check.viewCount ?? 1)
            let num = check.trainNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !num.isEmpty else { continue }
            let iso = isoFormatter.string(from: check.date)
            let day = dayFormatter.string(from: check.date)
            markPendingDayIfNeeded(day)
            let hourKey = String(check.hour)
            let weekdayKey = String(check.weekday)
            let cat = resolveTrainCategory(number: num, categoryDesc: check.category, destination: check.destination)

            if var entry = store.trainHistory[num] {
                entry.viewCount += count
                if iso > entry.lastSeen { entry.lastSeen = iso }
                if iso < entry.firstSeen { entry.firstSeen = iso }
                appendUniqueDay(day, to: &entry.daysSeen)
                entry.hoursHistogram[hourKey, default: 0] += count
                entry.weekdaysHistogram[weekdayKey, default: 0] += count
                store.trainHistory[num] = entry
            } else {
                store.trainHistory[num] = TelemetryTrainEntry(
                    number: num,
                    category: cat,
                    destination: check.destination,
                    origin: nil,
                    departureTime: nil,
                    viewCount: count,
                    searchCount: 0,
                    firstSeen: iso,
                    lastSeen: iso,
                    daysSeen: [day],
                    hoursHistogram: [hourKey: count],
                    weekdaysHistogram: [weekdayKey: count]
                )
            }
        }

        for r in usageTracker.routeUsages {
            recordRouteUsage(
                originName: r.originName,
                originID: r.originID,
                destinationName: r.destName,
                destinationID: r.destID,
                at: r.date
            )
        }

        for st in manager.viewedRecentStations + manager.recentStations {
            let key = normalizeKey(st.nomeLungo)
            if store.stationHistory[key] == nil {
                recordStationView(name: st.nomeLungo, vtID: st.vtID, at: st.lastViewedAt ?? Date())
            }
        }

        for tr in manager.viewedRecentTrains + manager.recentTrains {
            if store.trainHistory[tr.number] == nil {
                let endpoints = tr.parsedEndpoints
                recordTrainView(
                    number: tr.number,
                    category: tr.category,
                    destination: endpoints.destination,
                    origin: endpoints.origin,
                    departureTime: tr.departureTime,
                    at: tr.lastViewedAt ?? Date()
                )
            }
        }

        for route in manager.recentRoutes {
            let key = "\(normalizeKey(route.originName))->\(normalizeKey(route.destinationName))"
            if store.routeHistory[key] == nil {
                recordRouteUsage(
                    originName: route.originName,
                    originID: route.originID,
                    destinationName: route.destinationName,
                    destinationID: route.destinationID,
                    at: route.lastViewedAt ?? Date()
                )
            }
        }

        for q in manager.recentAssistantQueries {
            recordSearch(type: "assistant", query: q)
        }

        for trip in manager.recentViewedTrips {
            if store.viewedTripsHistory[trip.id] == nil {
                recordViewedTrip(trip, at: trip.lastViewedAt ?? Date())
            }
        }

        UserDefaults.standard.set(true, forKey: bootstrappedKey)
        flushToDiskNow()
    }

    // MARK: - Daily First-Open Sync (Ack-Before-Delete Delta Queue)

    /// Verifica se la risposta del server conferma esplicitamente il salvataggio del batch inviato per questo dispositivo.
    nonisolated static func canAcceptSyncAck(
        responseData: Data,
        statusCode: Int,
        expectedDeviceID: String,
        expectedBatchID: String
    ) -> Bool {
        guard (200...299).contains(statusCode) else { return false }
        guard let ack = try? JSONDecoder().decode(TelemetrySyncAckResponse.self, from: responseData) else {
            return false
        }
        guard ack.status?.lowercased() == "ok" else { return false }
        if let saved = ack.saved, !saved { return false }
        if let uid = ack.user_id?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !uid.isEmpty,
           uid != expectedDeviceID.lowercased() {
            return false
        }
        if let bid = ack.batch_id?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !bid.isEmpty,
           bid != expectedBatchID.lowercased() {
            return false
        }
        return true
    }

    /// Sottrae dallo store corrente solo il batch confermato dal server:
    /// se nessun nuovo evento è arrivato durante la chiamata HTTP, lo store locale viene azzerato completamente;
    /// eventuali nuovi eventi registrati in-flight vengono preservati per il prossimo invio.
    nonisolated static func subtractAcknowledgedStore(
        sent: TelemetryLocalStore,
        from current: TelemetryLocalStore
    ) -> TelemetryLocalStore {
        var next = current

        func subtractHistogram(_ sentHist: [String: Int], from curHist: [String: Int]) -> [String: Int] {
            var res = curHist
            for (k, v) in sentHist {
                let rem = (res[k] ?? 0) - v
                if rem > 0 {
                    res[k] = rem
                } else {
                    res.removeValue(forKey: k)
                }
            }
            return res
        }

        for (k, sentEntry) in sent.stationHistory {
            guard var cur = next.stationHistory[k] else { continue }
            cur.viewCount -= sentEntry.viewCount
            cur.searchCount = max(0, cur.searchCount - sentEntry.searchCount)
            cur.gpsConfirmedCount = max(0, cur.gpsConfirmedCount - sentEntry.gpsConfirmedCount)
            cur.hoursHistogram = subtractHistogram(sentEntry.hoursHistogram, from: cur.hoursHistogram)
            cur.weekdaysHistogram = subtractHistogram(sentEntry.weekdaysHistogram, from: cur.weekdaysHistogram)
            if cur.viewCount <= 0 {
                next.stationHistory.removeValue(forKey: k)
            } else {
                next.stationHistory[k] = cur
            }
        }

        for (k, sentEntry) in sent.trainHistory {
            guard var cur = next.trainHistory[k] else { continue }
            cur.viewCount -= sentEntry.viewCount
            cur.searchCount = max(0, cur.searchCount - sentEntry.searchCount)
            cur.hoursHistogram = subtractHistogram(sentEntry.hoursHistogram, from: cur.hoursHistogram)
            cur.weekdaysHistogram = subtractHistogram(sentEntry.weekdaysHistogram, from: cur.weekdaysHistogram)
            if cur.viewCount <= 0 {
                next.trainHistory.removeValue(forKey: k)
            } else {
                next.trainHistory[k] = cur
            }
        }

        for (k, sentEntry) in sent.lineHistory {
            guard var cur = next.lineHistory[k] else { continue }
            cur.viewCount -= sentEntry.viewCount
            cur.hoursHistogram = subtractHistogram(sentEntry.hoursHistogram, from: cur.hoursHistogram)
            cur.weekdaysHistogram = subtractHistogram(sentEntry.weekdaysHistogram, from: cur.weekdaysHistogram)
            if cur.viewCount <= 0 {
                next.lineHistory.removeValue(forKey: k)
            } else {
                next.lineHistory[k] = cur
            }
        }

        for (k, sentEntry) in sent.routeHistory {
            guard var cur = next.routeHistory[k] else { continue }
            cur.viewCount -= sentEntry.viewCount
            cur.hoursHistogram = subtractHistogram(sentEntry.hoursHistogram, from: cur.hoursHistogram)
            cur.weekdaysHistogram = subtractHistogram(sentEntry.weekdaysHistogram, from: cur.weekdaysHistogram)
            if cur.viewCount <= 0 {
                next.routeHistory.removeValue(forKey: k)
            } else {
                next.routeHistory[k] = cur
            }
        }

        for (k, sentEntry) in sent.searches {
            guard var cur = next.searches[k] else { continue }
            cur.count -= sentEntry.count
            if cur.count <= 0 {
                next.searches.removeValue(forKey: k)
            } else {
                next.searches[k] = cur
            }
        }

        if !sent.recentSearchEvents.isEmpty {
            let sentKeys = Set(sent.recentSearchEvents.map { "\($0.type)|\($0.query.lowercased())|\($0.timestamp)" })
            next.recentSearchEvents.removeAll { ev in
                sentKeys.contains("\(ev.type)|\(ev.query.lowercased())|\(ev.timestamp)")
            }
        }

        for (k, sentEntry) in sent.viewedTripsHistory {
            guard var cur = next.viewedTripsHistory[k] else { continue }
            cur.viewCount -= sentEntry.viewCount
            if cur.viewCount <= 0 {
                next.viewedTripsHistory.removeValue(forKey: k)
            } else {
                next.viewedTripsHistory[k] = cur
            }
        }

        for (k, sentEntry) in sent.infomobilityViews {
            guard var cur = next.infomobilityViews[k] else { continue }
            cur.viewCount -= sentEntry.viewCount
            if cur.viewCount <= 0 {
                next.infomobilityViews.removeValue(forKey: k)
            } else {
                next.infomobilityViews[k] = cur
            }
        }

        if next.isEmpty {
            next.pendingBatchID = nil
            next.oldestPendingDay = nil
        } else {
            next.pendingBatchID = UUID().uuidString.lowercased()
            next.oldestPendingDay = nil
        }
        return next
    }

    /// Invia i dati al server una volta al giorno, alla prima apertura dell'app della giornata (o subito se ci sono
    /// log arretrati di giorni precedenti rimasti in coda offline).
    /// Elimina i log locali SOLO dopo conferma esplicita (`status: "ok"`, `saved: true`) del server.
    func syncIfNeededForToday(manager: TrainManager, usageTracker: UsageTracker, force: Bool = false) {
        guard isCollectionEnabled else { return }

        bootstrapFromExistingHistoryIfNeeded(manager: manager, usageTracker: usageTracker)

        let todayKey = dayFormatter.string(from: Date())
        let lastSyncedDay = UserDefaults.standard.string(forKey: lastSyncDayKey)
        let hasBacklogFromEarlierDay = !store.isEmpty && (store.oldestPendingDay != nil && store.oldestPendingDay != todayKey)

        if !force && lastSyncedDay == todayKey && !hasBacklogFromEarlierDay {
            return
        }
        guard !isSyncing else { return }

        // Evita retry troppo ravvicinati in caso di errore di rete (minimo 2 minuti tra tentativi)
        if !force, let lastAttempt = lastSyncAttemptAt, Date().timeIntervalSince(lastAttempt) < 120 {
            return
        }

        isSyncing = true
        lastSyncAttemptAt = Date()

        // Riutilizza lo stesso batch_id sui retry di un batch non confermato per idempotenza lato server
        let batchID: String = {
            if let existing = store.pendingBatchID, !existing.isEmpty {
                return existing
            }
            let fresh = UUID().uuidString.lowercased()
            store.pendingBatchID = fresh
            return fresh
        }()
        let sentSnapshot = store
        flushToDiskNow()

        let payload = buildPayload(
            manager: manager,
            usageTracker: usageTracker,
            todayKey: todayKey,
            batchID: batchID,
            snapshot: sentSnapshot
        )
        guard let url = URL(string: syncURLString) else {
            isSyncing = false
            return
        }

        Task {
            defer {
                Task { @MainActor in
                    self.isSyncing = false
                }
            }
            do {
                let encoder = JSONEncoder()
                let bodyData = try encoder.encode(payload)

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 20
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(payload.device_id, forHTTPHeaderField: "X-Device-ID")
                if let tok = payload.apns_token, !tok.isEmpty {
                    request.setValue(tok, forHTTPHeaderField: "X-Device-Token")
                }
                request.httpBody = bodyData

                let (responseData, response) = try await URLSession.shared.data(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                if Self.canAcceptSyncAck(
                    responseData: responseData,
                    statusCode: statusCode,
                    expectedDeviceID: payload.device_id,
                    expectedBatchID: batchID
                ) {
                    let completedAt = self.isoFormatter.string(from: Date())
                    self.store = Self.subtractAcknowledgedStore(sent: sentSnapshot, from: self.store)
                    if !self.store.isEmpty && self.store.oldestPendingDay == nil {
                        self.store.oldestPendingDay = todayKey
                    }
                    self.flushToDiskNow()
                    UserDefaults.standard.set(todayKey, forKey: self.lastSyncDayKey)
                    UserDefaults.standard.set(completedAt, forKey: self.lastSyncAtKey)
                    print("[UserTelemetry] Sync giornaliero confermato dal server (\(todayKey), batch \(batchID.prefix(8))): coda locale svuotata.")
                } else {
                    print("[UserTelemetry] Sync non confermato (HTTP \(statusCode)), log locali mantenuti per il prossimo tentativo.")
                }
            } catch {
                print("[UserTelemetry] Errore rete durante sync giornaliero: \(error.localizedDescription). Log mantenuti in locale.")
            }
        }
    }

    private func loadSavedLinesForTelemetry() -> [TelemetryFavoriteLineDTO] {
        guard let data = UserDefaults.standard.data(forKey: "personalSavedRailwayLines_v1"),
              let lines = try? JSONDecoder().decode([PersonalRailwayLine].self, from: data) else {
            return []
        }
        return lines.map { line in
            TelemetryFavoriteLineDTO(
                line_id: line.id,
                code: line.code,
                name: line.name,
                kind: line.kind.rawValue,
                region: line.effectiveRegion
            )
        }
    }

    private func buildPayload(
        manager: TrainManager,
        usageTracker: UsageTracker,
        todayKey: String,
        batchID: String,
        snapshot: TelemetryLocalStore
    ) -> TelemetrySyncPayload {
        let nowISO = isoFormatter.string(from: Date())
        let deviceID = DeviceIdentityManager.shared.deviceID
        let apnsToken = manager.apnsToken ?? UserDefaults.standard.string(forKey: "apnsTokenKey_v1")
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let osVersion = UIDevice.current.systemVersion
        let deviceModel = currentDeviceModelIdentifier()
        let localeID = Locale.current.identifier
        let previousSync = UserDefaults.standard.string(forKey: lastSyncAtKey)

        let favStations = manager.myStations.map { st in
            TelemetryFavoriteStationDTO(
                name: st.name,
                vt_id: st.vtID,
                rfi_id: st.rfiID,
                lat: st.lat,
                lon: st.lon,
                added_date: st.addedDate.map { isoFormatter.string(from: $0) }
            )
        }

        let favTrains = manager.favoriteTrains.map { tr in
            let endpoints = tr.parsedEndpoints
            return TelemetryFavoriteTrainDTO(
                number: tr.number,
                category: tr.resolvedCategoryCode(),
                description: tr.description,
                origin: endpoints.origin,
                destination: endpoints.destination,
                departure_time: tr.departureTime,
                arrival_time: tr.arrivalTime,
                active_days: tr.activeDays,
                notify_delay: tr.notifyDelay ?? false,
                notify_departure: tr.notifyDeparture ?? false,
                notify_station_pass: tr.notifyStationPass ?? false,
                station_pass_name: tr.stationPassName,
                notify_platform_change: tr.notifyPlatformChange ?? false,
                added_date: tr.addedDate.map { isoFormatter.string(from: $0) }
            )
        }

        let favLines = loadSavedLinesForTelemetry()

        let favRoutes = manager.favoriteRoutes.map { r in
            TelemetryFavoriteRouteDTO(
                origin_name: r.originName,
                origin_id: r.originID,
                destination_name: r.destinationName,
                destination_id: r.destinationID,
                last_viewed_at: r.lastViewedAt.map { isoFormatter.string(from: $0) }
            )
        }

        let smartRoutes = manager.smartRoutes.map { sr in
            TelemetrySmartRouteDTO(origin_name: sr.originName, destination_name: sr.destinationName)
        }

        let savedTrips = manager.savedTrips.map { trip in
            TelemetrySavedTripDTO(
                id: trip.id,
                origin: trip.origin,
                destination: trip.destination,
                departure_time: trip.departureTime,
                arrival_time: trip.arrivalTime,
                duration: trip.duration,
                segments: trip.segments.map { seg in
                    TelemetrySavedTripSegmentDTO(
                        origin: seg.origin,
                        destination: seg.destination,
                        departure_time: seg.departureTime,
                        arrival_time: seg.arrivalTime,
                        train_number: seg.trainNumber,
                        train_category: seg.trainCategory
                    )
                },
                last_viewed_at: trip.lastViewedAt.map { isoFormatter.string(from: $0) }
            )
        }

        let commute = SupporterCommuteManager.shared
        let commuteDTO: TelemetryCommuteRoutineDTO? = {
            if commute.origins.isEmpty && commute.destinations.isEmpty { return nil }
            var habitTrainSet = Set<String>()
            for (_, sched) in commute.daySchedules {
                for t in sched.outboundTrains { habitTrainSet.insert(t.trainNumber) }
                for t in sched.returnTrains { habitTrainSet.insert(t.trainNumber) }
            }
            return TelemetryCommuteRoutineDTO(
                origins: commute.origins,
                destinations: commute.destinations,
                default_outbound_band: commute.defaultOutboundBand,
                default_return_band: commute.defaultReturnBand,
                active_weekdays: Array(commute.activeWeekdays).sorted(),
                proactive_alerts_enabled: commute.proactiveAlertsEnabled,
                scheduled_summary_enabled: commute.scheduledSummaryEnabled,
                habit_trains: Array(habitTrainSet).sorted()
            )
        }()

        let learnedHabits = usageTracker.learnedHabitsByTimeSlot(
            favoriteTrains: manager.favoriteTrains,
            favoriteStations: manager.myStations
        ).map { slot in
            TelemetryLearnedHabitSlotDTO(
                slot: slot.title,
                time_range: slot.timeRange,
                stations: slot.stations.map { s in
                    TelemetryLearnedStationDTO(
                        name: s.name,
                        total_views: s.totalViews,
                        distinct_days: s.distinctDays,
                        is_favorite: s.isFavorite,
                        strength: s.habitStrength
                    )
                },
                trains: slot.trains.map { t in
                    TelemetryLearnedTrainDTO(
                        number: t.number,
                        category: t.category,
                        destination: t.destination,
                        departure_time: t.departureTime,
                        total_views: t.totalViews,
                        distinct_days: t.distinctDays,
                        is_favorite: t.isFavorite,
                        strength: t.habitStrength
                    )
                }
            )
        }

        let sortedStations = snapshot.stationHistory.values
            .sorted { ($0.viewCount, $0.lastSeen) > ($1.viewCount, $1.lastSeen) }
            .prefix(250)
        let sortedTrains = snapshot.trainHistory.values
            .sorted { ($0.viewCount, $0.lastSeen) > ($1.viewCount, $1.lastSeen) }
            .prefix(250)
        let sortedLines = snapshot.lineHistory.values
            .sorted { ($0.viewCount, $0.lastSeen) > ($1.viewCount, $1.lastSeen) }
            .prefix(150)
        let sortedRoutes = snapshot.routeHistory.values
            .sorted { ($0.viewCount, $0.lastSeen) > ($1.viewCount, $1.lastSeen) }
            .prefix(200)
        let sortedSearches = snapshot.searches.values
            .sorted { ($0.count, $0.lastSeen) > ($1.count, $1.lastSeen) }
            .prefix(250)
        let sortedViewedTrips = snapshot.viewedTripsHistory.values
            .sorted { ($0.viewCount, $0.lastSeen) > ($1.viewCount, $1.lastSeen) }
            .prefix(100)
        let sortedInfomobility = snapshot.infomobilityViews.values
            .sorted { ($0.lastSeen, $0.viewCount) > ($1.lastSeen, $1.viewCount) }
            .prefix(100)

        return TelemetrySyncPayload(
            device_id: deviceID,
            apns_token: (apnsToken?.isEmpty == false) ? apnsToken : nil,
            platform: "ios",
            device_model: deviceModel,
            os_version: osVersion,
            app_version: appVersion,
            locale: localeID,
            has_support: manager.hasSupport(),
            strike_region: manager.strikeRegion,
            strike_notifications_enabled: manager.strikeNotificationsEnabled,
            remote_notifications_enabled: manager.remoteNotificationsEnabled,
            sync_day: todayKey,
            generated_at: nowISO,
            previous_sync_at: previousSync,
            payload_mode: "delta",
            batch_id: batchID,
            favorite_stations: favStations,
            favorite_trains: favTrains,
            favorite_lines: favLines,
            favorite_routes: favRoutes,
            smart_routes: smartRoutes,
            saved_trips: savedTrips,
            commute_routine: commuteDTO,
            learned_habits: learnedHabits,
            station_history: Array(sortedStations),
            train_history: Array(sortedTrains),
            line_history: Array(sortedLines),
            route_history: Array(sortedRoutes),
            searches: Array(sortedSearches),
            recent_search_events: Array(snapshot.recentSearchEvents.prefix(100)),
            viewed_trips_history: Array(sortedViewedTrips),
            infomobility_views: Array(sortedInfomobility)
        )
    }
}
