import Foundation

/// Uploads a serialized recording to the Rails server (#41, S4 — #52).
///
/// Posts the GPX to the existing `POST /activities` as multipart form data,
/// reusing the webview's session cookies (`WebSessionCookies`) for auth. The
/// endpoint answers `Accept: application/json` with `201 { id, url }` on success
/// and `422 { errors: [...] }` on a validation failure (the S0 contract,
/// `docs/native-recording/s0-gpx-upload-contract.md` §4–5). The field is named
/// `activity[fit_file]` even for GPX — the server dispatches on the `.gpx`
/// filename.
enum ActivityUploader {
    enum UploadError: Error {
        /// Server rejected the activity (e.g. missing sport); carries the
        /// server's `errors` messages for display.
        case validation([String])
        /// Transport/encoding failure or an unexpected status.
        case network(String)

        var message: String {
            switch self {
            case .validation(let errors):
                return errors.joined(separator: "\n")
            case .network(let description):
                return description
            }
        }
    }

    static func upload(
        gpx: String,
        sport: Sport,
        name: String?,
        visibility: Visibility,
        completion: @escaping (Result<URL, UploadError>) -> Void
    ) {
        let endpoint = AppConfig.baseURL.appending(path: "activities")

        WebSessionCookies.headerFields(for: endpoint) { cookieHeaders in
            let boundary = "Boundary-\(UUID().uuidString)"

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            for (field, value) in cookieHeaders {
                request.setValue(value, forHTTPHeaderField: field)
            }
            request.httpBody = body(gpx: gpx, sport: sport, name: name, visibility: visibility, boundary: boundary)

            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieAcceptPolicy = .never

            let task = URLSession(configuration: configuration).dataTask(with: request) { data, response, error in
                let result = makeResult(data: data, response: response, error: error)
                DispatchQueue.main.async { completion(result) }
            }
            task.resume()
        }
    }

    // MARK: - Response

    private static func makeResult(data: Data?, response: URLResponse?, error: Error?) -> Result<URL, UploadError> {
        if let error {
            return .failure(.network(error.localizedDescription))
        }
        guard let http = response as? HTTPURLResponse else {
            return .failure(.network("Réponse du serveur invalide."))
        }

        switch http.statusCode {
        case 201:
            guard let data,
                  let payload = try? JSONDecoder().decode(CreatedActivity.self, from: data),
                  let url = URL(string: payload.url) else {
                return .failure(.network("Réponse du serveur illisible."))
            }
            return .success(url)
        case 422:
            let errors = (data.flatMap { try? JSONDecoder().decode(ValidationErrors.self, from: $0) })?.errors
            return .failure(.validation(errors ?? ["L'activité n'a pas pu être créée."]))
        default:
            return .failure(.network("Erreur serveur (\(http.statusCode))."))
        }
    }

    private struct CreatedActivity: Decodable {
        let id: Int
        let url: String
    }

    private struct ValidationErrors: Decodable {
        let errors: [String]
    }

    // MARK: - Multipart body

    private static func body(gpx: String, sport: Sport, name: String?, visibility: Visibility, boundary: String) -> Data {
        var body = Data()
        appendField("activity[sport]", value: sport.rawValue, to: &body, boundary: boundary)
        appendField("activity[visibility]", value: visibility.rawValue, to: &body, boundary: boundary)
        if let name, !name.isEmpty {
            appendField("activity[name]", value: name, to: &body, boundary: boundary)
        }
        appendFile(
            "activity[fit_file]",
            filename: "recording.gpx",
            contentType: "application/gpx+xml",
            data: Data(gpx.utf8),
            to: &body,
            boundary: boundary
        )
        body.append("--\(boundary)--\r\n")
        return body
    }

    private static func appendField(_ name: String, value: String, to body: inout Data, boundary: String) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.append("\(value)\r\n")
    }

    private static func appendFile(
        _ name: String,
        filename: String,
        contentType: String,
        data: Data,
        to body: inout Data,
        boundary: String
    ) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        body.append("\r\n")
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
