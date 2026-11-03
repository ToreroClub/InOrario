import Foundation

// MARK: - AppNetworkError

public enum AppNetworkError: LocalizedError, Sendable, Equatable {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, data: Data? = nil)
    case decodingFailed(String)
    case timeout
    case cancelled
    case noConnection
    case underlying(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL non valido."
        case .invalidResponse:
            return "Risposta non valida dal server."
        case .httpError(let code, _):
            return "Errore server HTTP \(code)."
        case .decodingFailed(let detail):
            return "Errore di decodifica: \(detail)"
        case .timeout:
            return "Richiesta scaduta (timeout)."
        case .cancelled:
            return "Richiesta annullata."
        case .noConnection:
            return "Connessione di rete assente."
        case .underlying(let msg):
            return msg
        }
    }
    
    public static func == (lhs: AppNetworkError, rhs: AppNetworkError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL),
             (.invalidResponse, .invalidResponse),
             (.timeout, .timeout),
             (.cancelled, .cancelled),
             (.noConnection, .noConnection):
            return true
        case (.httpError(let lCode, _), .httpError(let rCode, _)):
            return lCode == rCode
        case (.decodingFailed(let lMsg), .decodingFailed(let rMsg)):
            return lMsg == rMsg
        case (.underlying(let lMsg), .underlying(let rMsg)):
            return lMsg == rMsg
        default:
            return false
        }
    }
}

// MARK: - RequestDeduplicator

actor RequestDeduplicator<T: Sendable> {
    private var inFlight: [String: Task<T, Error>] = [:]
    
    func execute(
        key: String,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        if let ongoing = inFlight[key] {
            AppLogger.duplicateAvoided(key: key)
            return try await ongoing.value
        }
        
        let task = Task<T, Error> {
            try await operation()
        }
        inFlight[key] = task
        
        do {
            let result = try await task.value
            inFlight.removeValue(forKey: key)
            return result
        } catch {
            inFlight.removeValue(forKey: key)
            throw error
        }
    }
}

// MARK: - NetworkService

class NetworkService {
    static let shared = NetworkService()
    
    private let session: URLSession
    private let deduplicator = RequestDeduplicator<(Data, URLResponse)>()
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12.0
        config.timeoutIntervalForResource = 25.0
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }
    
    private func injectDeviceTokenIfNeeded(to request: inout URLRequest) {
        if let urlString = request.url?.absoluteString, urlString.contains("gestioneinorario.toreroclub.com") {
            if let token = UserDefaults.standard.string(forKey: "apnsTokenKey_v1") {
                request.setValue(token, forHTTPHeaderField: "X-Device-Token")
            }
        }
    }
    
    private func prepareRequest(_ request: inout URLRequest) {
        if request.timeoutInterval <= 0 || request.timeoutInterval == 60.0 {
            request.timeoutInterval = 12.0
        }
        injectDeviceTokenIfNeeded(to: &request)
    }
    
    private func isTransient(error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }
        if case AppNetworkError.httpError(let code, _) = error {
            return code == 502 || code == 503 || code == 504
        }
        return false
    }
    
    private func mapError(_ error: Error) -> AppNetworkError {
        if let appErr = error as? AppNetworkError {
            return appErr
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return .cancelled
            case .timedOut:
                return .timeout
            case .notConnectedToInternet, .networkConnectionLost:
                return .noConnection
            case .badURL:
                return .invalidURL
            default:
                return .underlying(urlError.localizedDescription)
            }
        }
        return .underlying(error.localizedDescription)
    }
    
    private func performRequestWithRetry(request: URLRequest) async throws -> (Data, URLResponse) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let urlHost = request.url?.host ?? "unknown"
        var lastError: Error?
        
        for attempt in 0...1 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            guard !Task.isCancelled else { throw AppNetworkError.cancelled }
            
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw AppNetworkError.invalidResponse
                }
                guard (200...299).contains(http.statusCode) else {
                    throw AppNetworkError.httpError(statusCode: http.statusCode, data: data)
                }
                let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                let retryTag = attempt > 0 ? " (retry)" : ""
                AppLogger.duration(
                    method: request.httpMethod ?? "GET",
                    endpoint: "\(urlHost)\(retryTag)",
                    statusCode: http.statusCode,
                    durationMs: Int(duration)
                )
                return (data, response)
            } catch {
                guard !Task.isCancelled else { throw AppNetworkError.cancelled }
                lastError = error
                if attempt == 0 && isTransient(error: error) {
                    AppLogger.network("Retry transient error for \(urlHost): \(error.localizedDescription)")
                    continue
                } else {
                    break
                }
            }
        }
        
        throw mapError(lastError ?? AppNetworkError.invalidResponse)
    }
    
    static func deduplicationKey(for request: URLRequest) -> String? {
        guard let url = request.url?.absoluteString else { return nil }
        let method = request.httpMethod?.uppercased() ?? "GET"
        let headers = (request.allHTTPHeaderFields ?? [:])
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        return "\(method):\(url)|\(headers)"
    }
    
    private func execute(
        request: URLRequest,
        deduplicate: Bool = true
    ) async throws -> (Data, URLResponse) {
        if deduplicate, request.httpMethod?.uppercased() == "GET", let key = NetworkService.deduplicationKey(for: request) {
            return try await deduplicator.execute(key: key) { [weak self] in
                guard let self = self else { throw AppNetworkError.cancelled }
                return try await self.performRequestWithRetry(request: request)
            }
        } else {
            return try await performRequestWithRetry(request: request)
        }
    }
    
    // MARK: - Public API Calls
    
    func post(endpoint: String, payload: [String: Any]) async throws -> (Data, URLResponse) {
        guard let url = URL(string: "https://gestioneinorario.toreroclub.com\(endpoint)") else {
            throw AppNetworkError.invalidURL
        }
        return try await post(url: url, payload: payload)
    }
    
    func postData(endpoint: String, payload: [String: Any]) async throws -> Data {
        let (data, _) = try await post(endpoint: endpoint, payload: payload)
        return data
    }
    
    func post(url: URL, payload: [String: Any]) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        prepareRequest(&request)
        return try await execute(request: request, deduplicate: false)
    }
    
    func post(request: URLRequest) async throws -> (Data, URLResponse) {
        var req = request
        prepareRequest(&req)
        return try await execute(request: req, deduplicate: false)
    }
    
    func get(url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        prepareRequest(&request)
        return try await execute(request: request, deduplicate: true)
    }
    
    func get(request: URLRequest) async throws -> (Data, URLResponse) {
        var req = request
        prepareRequest(&req)
        return try await execute(request: req, deduplicate: true)
    }
    
    func getData(url: URL) async throws -> Data {
        let (data, _) = try await get(url: url)
        return data
    }
    
    func getData(request: URLRequest) async throws -> Data {
        let (data, _) = try await get(request: request)
        return data
    }
}
