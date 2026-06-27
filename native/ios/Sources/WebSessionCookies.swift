import Foundation
import WebKit

/// Shares the Hotwire Native webview's logged-in session with native `URLSession`
/// requests (#41).
///
/// Both the GPX download (`FileDownloader`) and the recording upload
/// (`ActivityUploader`) need to ride the same signed `session_id` cookie the
/// WKWebView already holds — opening a bare `URLSession` would go out
/// unauthenticated and the server would bounce to the login page. We build the
/// `Cookie` header explicitly: handing cookies to a private `HTTPCookieStorage`
/// does not reliably feed them to the session.
enum WebSessionCookies {
    /// Resolves the `Cookie`-bearing request header fields for `url` from the
    /// default website data store, filtered to cookies whose domain matches the
    /// request host. The completion is invoked on the main queue.
    static func headerFields(for url: URL, completion: @escaping ([String: String]) -> Void) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            let host = url.host ?? ""
            let relevantCookies = cookies.filter { cookie in
                let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
                return host == domain || host.hasSuffix("." + domain)
            }
            completion(HTTPCookie.requestHeaderFields(with: relevantCookies))
        }
    }
}
