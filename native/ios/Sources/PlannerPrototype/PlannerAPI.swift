// PROTOTYPE — throwaway (wayfinder #21). Rides the webview cookie; the real
// design is bearer auth (#10) and the JSON contract of #20.
import Foundation

enum PlannerAPI {
    struct APIError: Error, CustomStringConvertible {
        let status: Int
        let code: String
        var description: String { "\(code) (\(status))" }
    }

    struct Preview {
        let coordinates: [Coord]
        let distanceMeters: Double?
        let elevationGainMeters: Double?
        let elevationSamples: [(Double, Double)]
    }

    static func preview(sport: String, waypoints: [Coord]) async throws -> Preview {
        let body = try JSONSerialization.data(withJSONObject: ["sport": sport, "waypoints": waypoints.map(\.pair)])
        let json = try await request("planned_routes/preview", body: body, contentType: "application/json")
        let coords = (json["coordinates"] as? [[Double]] ?? []).map { Coord(lng: $0[0], lat: $0[1]) }
        let samples = (json["elevation_samples"] as? [[Double]] ?? []).map { ($0[0], $0[1]) }
        return Preview(
            coordinates: coords,
            distanceMeters: json["distance_meters"] as? Double,
            elevationGainMeters: json["elevation_gain_meters"] as? Double,
            elevationSamples: samples
        )
    }

    static func importGpx(data: Data, filename: String) async throws -> (waypoints: [Coord], name: String?) {
        let boundary = "velo-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"gpx_source\"; filename=\"\(filename)\"\r\nContent-Type: application/gpx+xml\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        let json = try await request("planned_routes/import_gpx", body: body, contentType: "multipart/form-data; boundary=\(boundary)")
        let points = (json["waypoints"] as? [[Double]] ?? []).map { Coord(lng: $0[0], lat: $0[1]) }
        return (points, json["name"] as? String)
    }

    static func save(name: String, sport: String, waypoints: [Coord]) async throws -> URL? {
        let waypointsJson = String(data: try JSONSerialization.data(withJSONObject: waypoints.map(\.pair)), encoding: .utf8)!
        let body = try JSONSerialization.data(withJSONObject: [
            "planned_route": ["name": name, "sport": sport, "visibility": "private", "waypoints_json": waypointsJson],
        ])
        let json = try await request("planned_routes", body: body, contentType: "application/json")
        return (json["url"] as? String).flatMap(URL.init(string:))
    }

    private static func request(_ path: String, body: Data, contentType: String) async throws -> [String: Any] {
        let url = AppConfig.baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let cookies = await withCheckedContinuation { cont in
            WebSessionCookies.headerFields(for: url) { cont.resume(returning: $0) }
        }
        cookies.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            throw APIError(status: status, code: json["error"] as? String ?? "http_error")
        }
        return json
    }
}
