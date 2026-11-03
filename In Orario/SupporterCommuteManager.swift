import Foundation
import SwiftUI
import Combine
import StoreKit

// MARK: - Models

struct DayCommuteSchedule: Codable, Equatable {
    var isEnabled: Bool = true
    var outboundBand: String = "07:00 - 08:00"
    var returnBand: String = "17:00 - 18:00"
}

struct CommuteScheduleDTO: Codable, Identifiable, Equatable {
    var id: String { "\(type)_\(time)" }
    var type: String // "outbound" or "return"
    var time: String // "HH:mm - HH:mm"
    var weekdays: [Int] // 1=Mon .. 7=Sun
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

// MARK: - City/Station Formatter

func formatCityOrStationSummary(_ stations: [String]) -> String {
    guard !stations.isEmpty else { return "" }
    
    func cleanStationDisplay(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("milano ") {
            let rest = trimmed.dropFirst(7).trimmingCharacters(in: .whitespaces)
            return "Milano \(rest.capitalized)"
        }
        return trimmed.capitalized
    }
    
    let cleanedStations = stations.map(cleanStationDisplay)
    if cleanedStations.count == 1 { return cleanedStations[0] }
    
    let majorCities = ["Milano", "Torino", "Roma", "Genova", "Napoli", "Bologna", "Firenze", "Venezia", "Verona"]
    for city in majorCities {
        let allInCity = stations.allSatisfy { st in
            st.localizedCaseInsensitiveContains(city)
        }
        if allInCity {
            return city
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
    @AppStorage("commute_prompt_snoozed_until_v1") private var snoozedUntilDouble: Double = 0
    @AppStorage("commute_prompt_permanently_dismissed_v1") var promptPermanentlyDismissed: Bool = false
    @AppStorage("pinned_plan_b_json_v1") private var pinnedPlanBJSON: String = ""
    @AppStorage("commute_chosen_alternative_id_v1") private var chosenAlternativeIdRaw: String = ""
    
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
    
    // Active Plan B received from server or manual check
    @Published var activePlanB: PlanBReportDTO? = nil
    @Published var pinnedPlanB: PlanBReportDTO? = nil
    @Published var chosenAlternativeId: String? = nil {
        didSet { chosenAlternativeIdRaw = chosenAlternativeId ?? "" }
    }
    @Published var isCalculatingPlanB: Bool = false
    @Published var lastSyncError: String? = nil
    
    private init() {
        loadData()
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
    
    // MARK: - Server Sync
    
    func syncRoutineWithServer() async {
        let supID = getSupporterEternalID()
        guard !supID.isEmpty else { return }
        guard !origins.isEmpty && !destinations.isEmpty else { return }
        
        let token = UserDefaults.standard.string(forKey: "apnsTokenKey_v1") ?? UserDefaults.standard.string(forKey: "deviceToken") ?? ""
        let model = UIDevice.current.model
        
        var schedulesPayload: [[String: Any]] = []
        
        if customizePerDay {
            for day in 1...7 {
                if let config = daySchedules[day], config.isEnabled {
                    schedulesPayload.append([
                        "type": "outbound",
                        "time": config.outboundBand,
                        "weekdays": [day]
                    ])
                    schedulesPayload.append([
                        "type": "return",
                        "time": config.returnBand,
                        "weekdays": [day]
                    ])
                }
            }
        } else {
            schedulesPayload = [
                [
                    "type": "outbound",
                    "time": defaultOutboundBand,
                    "weekdays": Array(activeWeekdays)
                ],
                [
                    "type": "return",
                    "time": defaultReturnBand,
                    "weekdays": Array(activeWeekdays)
                ]
            ]
        }
        
        let payload: [String: Any] = [
            "supporter_id": supID,
            "device_token": token,
            "platform": "ios",
            "device_model": model,
            "origins": origins,
            "destinations": destinations,
            "schedules": schedulesPayload,
            "proactive_alerts": proactiveAlertsEnabled
        ]
        
        do {
            let res = try await NetworkService.shared.post(endpoint: "/supporter/commute", payload: payload)
            print("[+] Abitudini di viaggio sincronizzate con il server: \(res)")
            self.lastSyncError = nil
        } catch {
            print("[-] Errore sincronizzazione abitudini di viaggio: \(error.localizedDescription)")
            self.lastSyncError = error.localizedDescription
        }
    }
    
    func requestManualPlanB(origins customOrigins: [String]? = nil, destinations customDestinations: [String]? = nil, for returnTrip: Bool = false, userLat: Double? = nil, userLon: Double? = nil) async {
        isCalculatingPlanB = true
        chosenAlternativeId = nil
        defer { isCalculatingPlanB = false }
        
        let effectiveOrigins = customOrigins ?? self.origins
        let effectiveDestinations = customDestinations ?? self.destinations
        
        let startStations = returnTrip ? effectiveDestinations : effectiveOrigins
        let endStations = returnTrip ? effectiveOrigins : effectiveDestinations
        let targetBand = returnTrip ? defaultReturnBand : defaultOutboundBand
        
        guard !startStations.isEmpty && !endStations.isEmpty else { return }
        
        var payload: [String: Any] = [
            "origins": startStations,
            "destinations": endStations,
            "time": targetBand,
            "incident_type": "simulation"
        ]
        if let lat = userLat, let lon = userLon {
            payload["user_lat"] = lat
            payload["user_lon"] = lon
        }
        
        do {
            let data = try await NetworkService.shared.postData(endpoint: "/supporter/plan_b", payload: payload)
            let report = try JSONDecoder().decode(PlanBReportDTO.self, from: data)
            self.activePlanB = report
            self.lastSyncError = nil
        } catch {
            print("[-] Errore richiesta manuale alternative: \(error.localizedDescription)")
            self.lastSyncError = error.localizedDescription
            self.activePlanB = nil
        }
    }
}
