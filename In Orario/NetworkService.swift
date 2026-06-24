import Foundation

class NetworkService {
    static let shared = NetworkService()
    
    private init() {}
    
    // MARK: - API Calls
    
    func post(url: URL, payload: [String: Any]) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return try await URLSession.shared.data(for: request)
    }
    
    func get(url: URL) async throws -> (Data, URLResponse) {
        let request = URLRequest(url: url)
        return try await URLSession.shared.data(for: request)
    }
    
    func get(request: URLRequest) async throws -> (Data, URLResponse) {
        return try await URLSession.shared.data(for: request)
    }
}
