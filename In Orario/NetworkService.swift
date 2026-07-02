import Foundation

class NetworkService {
    static let shared = NetworkService()
    
    private init() {}
    
    private func injectDeviceTokenIfNeeded(to request: inout URLRequest) {
        if let urlString = request.url?.absoluteString, urlString.contains("gestioneinorario.toreroclub.com") {
            if let token = UserDefaults.standard.string(forKey: "apnsTokenKey_v1") {
                request.setValue(token, forHTTPHeaderField: "X-Device-Token")
            }
        }
    }
    
    // MARK: - API Calls
    
    func post(url: URL, payload: [String: Any]) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        injectDeviceTokenIfNeeded(to: &request)
        return try await URLSession.shared.data(for: request)
    }
    
    func get(url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        injectDeviceTokenIfNeeded(to: &request)
        return try await URLSession.shared.data(for: request)
    }
    
    func get(request: URLRequest) async throws -> (Data, URLResponse) {
        var req = request
        injectDeviceTokenIfNeeded(to: &req)
        return try await URLSession.shared.data(for: req)
    }
}
