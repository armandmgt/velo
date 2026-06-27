import HotwireNative
import UIKit

/// Downloads a file the WKWebView can't render (e.g. a GPX export served as an
/// `application/gpx+xml` attachment) and hands it to a share sheet so the user
/// can save it to Files, AirDrop it, etc.
///
/// Hotwire Native would otherwise propose a regular visit for the link, push a
/// web screen onto the stack, and surface an error when WKWebView fails to
/// display the attachment. We intercept those proposals in `SceneDelegate` and
/// route them here instead.
///
/// The private export route (`/planned_routes/:id.gpx`) requires the logged-in
/// session, so we copy the WKWebView's cookies into the download session rather
/// than opening Safari (which has its own, unauthenticated cookie store).
enum FileDownloader {
    static func download(from url: URL, presentingFrom navigator: Navigator) {
        // Reuse the webview's session cookies (see WebSessionCookies) so the
        // private export route is fetched as the logged-in user rather than
        // redirected to the login page.
        WebSessionCookies.headerFields(for: url) { cookieHeaders in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieAcceptPolicy = .never

            var request = URLRequest(url: url)
            for (field, value) in cookieHeaders {
                request.setValue(value, forHTTPHeaderField: field)
            }

            let session = URLSession(configuration: configuration)
            let task = session.downloadTask(with: request) { tempURL, response, error in
                let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
                guard
                    error == nil,
                    let tempURL,
                    let response = response as? HTTPURLResponse,
                    (200..<300).contains(response.statusCode),
                    // A redirect to the login page would be followed and arrive
                    // here as HTML — treat that (lost session) as a failure
                    // rather than saving the login page as a `.gpx` file.
                    !contentType.contains("text/html")
                else {
                    DispatchQueue.main.async { presentFailure(from: navigator) }
                    return
                }

                let filename = response.suggestedFilename ?? url.lastPathComponent
                let destination = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try? FileManager.default.removeItem(at: destination)

                do {
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                } catch {
                    DispatchQueue.main.async { presentFailure(from: navigator) }
                    return
                }

                DispatchQueue.main.async { presentShareSheet(for: destination, from: navigator) }
            }
            task.resume()
        }
    }

    private static func presentShareSheet(for fileURL: URL, from navigator: Navigator) {
        let presenter = topViewController(navigator)
        let activityController = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        // Anchor the popover on iPad, where a share sheet without a source view crashes.
        activityController.popoverPresentationController?.sourceView = presenter.view
        activityController.popoverPresentationController?.sourceRect = CGRect(
            x: presenter.view.bounds.midX,
            y: presenter.view.bounds.midY,
            width: 0,
            height: 0
        )
        presenter.present(activityController, animated: true)
    }

    private static func presentFailure(from navigator: Navigator) {
        let alert = UIAlertController(
            title: NSLocalizedString("Téléchargement échoué", comment: "Download failed alert title"),
            message: NSLocalizedString("Le fichier n'a pas pu être téléchargé.", comment: "Download failed alert message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        topViewController(navigator).present(alert, animated: true)
    }

    private static func topViewController(_ navigator: Navigator) -> UIViewController {
        var top: UIViewController = navigator.activeNavigationController
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
