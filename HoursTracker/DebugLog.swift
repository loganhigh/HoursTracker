import Foundation

/// Debug-only logging. No-op in release builds for App Store.
/// Sends logs via HTTP so they reach host debug.log when app runs in simulator.
enum DebugLog {
    private static let ingestURL = "http://127.0.0.1:7243/ingest/24b119e7-7f91-4f89-8be5-eceea63129d6"

    static func log(location: String, message: String, hypothesisId: String? = nil, data: [String: Any] = [:]) {
        #if DEBUG
        var payload: [String: Any] = [
            "location": location,
            "message": message,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]
        if let id = hypothesisId { payload["hypothesisId"] = id }
        if !data.isEmpty { payload["data"] = data }
        guard let json = try? JSONSerialization.data(withJSONObject: payload),
              let url = URL(string: ingestURL) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = json as Data?
        let task = URLSession.shared.dataTask(with: req) { (_: Data?, _: URLResponse?, _: Error?) in }
        task.resume()
        #endif
    }
}
