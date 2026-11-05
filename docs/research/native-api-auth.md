# Native API auth that shares the Hotwire session

Research for [Native API auth that shares the Hotwire session (#10)](https://github.com/armandmgt/velo/issues/10),
part of the map [#4](https://github.com/armandmgt/velo/issues/4). It builds on the
mixed-tabs spike ([#8](https://github.com/armandmgt/velo/issues/8)) and
[ADR 0006](../adr/0006-core-screens-are-native.md), and feeds
[JSON API for the store v1 native screens (#20)](https://github.com/armandmgt/velo/issues/20).
Researched 2026-11-05.

**The question.** The native SwiftUI / Compose screens need to call a JSON API. How
should they authenticate against Velo's Rails 8 auth (custom `Session` model, signed
`session_id` cookie, no Devise), while the remaining Hotwire webviews stay signed in
with the same session? Options: **(a)** bearer tokens tied to `Session` rows,
**(b)** reusing the webview cookie in `URLSession` / OkHttp, **(c)** bridging a
native token into the WKWebView / Android WebView cookie stores.

Each claim is marked **[fact]** (read in a primary source, in this repo, or seen in
the spike) or **[inference]** (my reasoning from facts; verify before relying on it).

## TL;DR

- **Use (a), minted from (b).** Sign-in stays a Hotwire page, as ADR 0006 says. Once
  the webview is signed in, native swaps its cookie **once** for a bearer token signed
  for **the same `Session` row** (`generates_token_for :native_api`). From then on
  native screens send `Authorization: Bearer …` and never touch the cookie store.
  Drop (c): it only matters when sign-in is native, and here it isn't.
- **One row, two credentials, one lifetime.** The webview holds the cookie, native
  holds the token. Both resolve to the same `Session` row, so destroying that row
  (sign-out, password reset, account deletion) kills both at once. The pattern is
  already in the repo: service accounts use `generates_token_for` on `Session` with
  `authenticate_with_http_token` (`ServiceAccountAuthentication`).
- **Storage:** iOS Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
  Android: app-private storage, encrypted with an Android Keystore key.
  `EncryptedSharedPreferences` is deprecated.
- **Unauthenticated JSON gets a 401, not a 302.** `request_authentication` answers
  `401` with `WWW-Authenticate` for JSON requests and keeps the HTML redirect.
  Bearer tokens count only on JSON requests, so the webview stays cookie-only.
- **On a 401, native tries one silent re-exchange** with the webview cookie. That
  covers "the web signed in again". If that also fails, a single app-level
  `signOutLocally()` wipes the token and the cookies and swaps to the sign-in root.
  The web route (`is_after_sign_out_path`) uses the same function.
- **Testability is the deciding plus.** Every rule is a Rails integration test
  (header in, status out). The native side is a plain string behind a
  `TokenStore` / `CookieSource` seam, tested with Swift Testing + `URLProtocol` stubs
  and JUnit + OkHttp `MockWebServer`. Only the end-to-end "sign in on the web, the
  native list loads" case needs Maestro.

## What the repo has today

- **Auth is the Rails 8 generator's, almost unchanged.** `Authentication#resume_session`
  looks up `Session.find_by(id: cookies.signed[:session_id])`.
  `start_new_session_for` creates a `Session` row (user_agent, ip_address) and sets
  `cookies.signed.permanent[:session_id]` with `httponly: true, same_site: :lax`.
  `terminate_session` destroys the row and deletes the cookie
  (`app/controllers/concerns/authentication.rb`; generator template
  `railties-8.1.4/…/authentication/templates/app/controllers/concerns/authentication.rb.tt`). [fact]
- **Nothing expires.** `permanent` means "expires in 20 years"
  (`actionpack-8.1.4/lib/action_dispatch/middleware/cookies.rb`), and nothing prunes
  `sessions` rows. `updated_at` isn't touched on use, so there is no "last seen" to
  expire on. [fact]
- **Server-side revocation already exists**, always by destroying rows:
  `SessionsController#destroy` (the current session),
  `PasswordsController#update` (`@user.sessions.destroy_all`), and
  `UsersController#destroy` (`has_many :sessions, dependent: :destroy`). There's no
  "your devices" screen. [fact]
- **`request_authentication` always redirects.** It stores `return_to` in the session
  and calls `redirect_to new_session_path`, whatever the format. That is the 302 the
  spike hit. [fact]
- **A bearer-token mechanism already exists, scoped to service accounts.**
  `ServiceAccountSession` adds `generates_token_for :service_account_api { created_at.to_i }`
  to `Session`. `ServiceAccountAuthentication` overrides `resume_session` to
  `super || find_session_by_token` (via `authenticate_with_http_token`). It accepts the
  token only when `session.service_account?` is true. It skips CSRF only when the token
  actually resolves. It is included only in `Admin::AdminController`, and a test
  (`test/integration/service_account_auth_test.rb`) pins that "a service-account token
  is not accepted outside the admin namespace". Revocation is `Session#destroy`. [fact]
- **JSON writes skip CSRF today.** `ActivitiesController` has
  `protect_from_forgery with: :exception, unless: -> { request.format.json? }`, for a
  future offline upload queue that "rides the signed `session_id` cookie". Only the
  cookie's `SameSite=Lax` stops a cross-site JSON write. [fact]
- **Native code already borrows the webview cookie for downloads.** iOS:
  `WebSessionCookies` reads `WKWebsiteDataStore.default().httpCookieStore.getAllCookies`,
  filters by host and builds a `Cookie` header. Its comment notes that a private
  `HTTPCookieStorage` "does not reliably feed them to the session". `FileDownloader`
  uses it and treats a `text/html` answer as "lost session". Android:
  `FileDownloadRouteDecisionHandler` hands `CookieManager.getInstance().getCookie(url)`
  to `DownloadManager`. [fact]
- **Hotwire Native iOS leaves the data store alone.** `HotwireConfig.makeWebViewConfiguration`
  sets a shared `WKProcessPool` but never sets `websiteDataStore`. Apple's
  `WKWebsiteDataStore` docs say a `WKWebViewConfiguration` then uses `default()`,
  "which saves website data persistently to disk". That's why `WebSessionCookies`
  reads `default()`. [fact]
- **The shells' auth flow.** Both start on an unauthenticated navigator at
  `/session/new`. `SessionsController#new` redirects an already signed-in cookie to
  root. The layout's `sessions/_meta` mounts `bridge--authentication`, whose `connect`
  makes iOS `SceneDelegate.didSignIn` / Android `AuthenticationComponent` swap to the
  tabs. Sign-out works the other way: a tab navigator proposing `/session/new`
  (path-config `is_after_sign_out_path: true`) triggers `SceneDelegate.didSignOut` /
  `SignOutRouteDecisionHandler` → `LoginActivity`. **The trigger is a web visit only.**
  No native code path can start it. [fact]
- **No native push registration exists yet.** The `push-subscription` bridge
  controller is in the web layout, but neither shell registers a matching component. [fact]
- Android has `android:allowBackup="false"` and pulls OkHttp 5.3.2 in through
  `dev.hotwire:core:1.2.8` (runtime scope; latest core is 1.4.1). [fact]

### What the spike (#8) showed

- Native lists that read the webview cookie (iOS via `WebSessionCookies`, Android via
  `CookieManager`) worked across a web sign-out and sign-in. This includes the
  `httponly` `session_id` cookie, which both native cookie APIs return. [fact, spike]
- After a server-side revocation, `GET /activities.json` answered `302` to the HTML
  login page. iOS `URLSession.shared` followed it and got HTML. Android
  (`instanceFollowRedirects = false`) got `302`. Neither screen had a way back to
  sign-in. [fact, spike]

## External guidance

- **Hotwire Native has no auth API and no auth guide.** The closest first-party text
  is the Turbo iOS [Authentication.md](https://github.com/hotwired/turbo-ios/blob/main/Docs/Authentication.md)
  (the predecessor library). Its guidance:
  - "The framework however doesn't provide any auth-specific handling or APIs, that's
    completely up to each app."
  - Cookie-only apps should make cookies "persistent, not session cookies".
  - When both web and native make authenticated requests: "you can authenticate
    natively and pass credentials to the web view, or authenticate in the web view and
    pass credentials to native."
  - **37signals' own apps go native → web.** Basecamp 3 and HEY authenticate natively,
    keep an OAuth token in the Keychain, and send it as a header from `URLSession`
    ("the same token" also serves share, widget and watch extensions). Basecamp then
    authenticates the web view with a hidden `WKWebView` request carrying the OAuth
    header, which sets cookies (sharing the `WKProcessPool`). HEY gets cookies back with
    the OAuth response and sets them on the cookie stores directly. [fact]
  - I found no auth page on native.hotwired.dev. [fact as of this search]
- **Hotwire Native Android 1.4.0** ([release](https://github.com/hotwired/hotwire-native-android/releases/tag/1.4.0)):
  "The library's own HTTP requests now send each host only its own WebView cookies,
  including on redirects." So the library itself treats `CookieManager` as the source
  of truth for its own requests. Velo is on 1.2.8. [fact]
- **Rails token auth** (`actionpack-8.1.4/…/metal/http_authentication.rb`):
  - `TOKEN_REGEX = /^(Token|Bearer)\s+/`, so `Authorization: Bearer x` works with
    `authenticate_with_http_token`.
  - `request_http_token_authentication` sets `WWW-Authenticate: Token realm="Application"`
    and renders plain text with `401`. Rails `main` adds a `scheme:` keyword to send
    `Bearer` instead, but 8.1.4 doesn't have it. [fact]
- **`generates_token_for`** ([API docs](https://api.rubyonrails.org/classes/ActiveRecord/TokenFor/ClassMethods.html),
  `activerecord-8.1.4/lib/active_record/token_for.rb`):
  - "Tokens are signed so that they are tamper-proof." They're produced with
    `message_verifier.generate(…, purpose: full_purpose)`, where the purpose string
    includes the class and purpose name, and nothing is stored.
  - "By default, tokens do not expire"; `expires_in` is optional.
  - If the block's value changes, "the token will be treated as invalid".
  - So a `:native_api` token can't be replayed as a `:service_account_api` token, and
    the other way round.
  - Revoking means the row (and so `find_by_token_for`) is gone. Rotating
    `secret_key_base` kills every token, and every signed cookie with them. [fact; the
    rotation consequence is inference]
- **`allow_browser`** (`ApplicationController` has `allow_browser versions: :modern`)
  blocks only when the UA parses as a known browser with a version below the minimum
  (`blocked? = user_agent_version_reported? && unsupported_browser?`,
  [allow_browser.rb](https://github.com/rails/rails/blob/main/actionpack/lib/action_controller/metal/allow_browser.rb)).
  A `Velo/1.0 CFNetwork/…` or `okhttp/5.x` UA should pass, but set an explicit app UA
  and cover it with a test. [fact; "should pass" is inference]
- **Apple:**
  - [`WKHTTPCookieStore`](https://developer.apple.com/documentation/webkit/wkhttpcookiestore)
    "manages the HTTP cookies associated with a particular web view". It offers async
    `getAllCookies`, `setCookie`, `delete` and an observer (`add(_:)`), and you get it
    from the data store, never construct it.
  - [`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly):
    readable after the first unlock until restart, "recommended for items that need to
    be accessed by background applications". Such items "do not migrate to a new
    device". [fact]
- **Android:**
  - [`CookieManager`](https://developer.android.com/reference/android/webkit/CookieManager)
    is a singleton. `getCookie(url)` returns a `Cookie`-header string.
    `setCookie(url, value[, callback])` takes a `Set-Cookie`-format value.
    `removeAllCookies` is async. `flush()` "ensures all cookies … are written to
    persistent storage".
  - [`androidx.security:security-crypto`](https://developer.android.com/jetpack/androidx/releases/security)
    1.1.0-alpha07 / 1.1.0 "Deprecated all APIs in favour of existing platform APIs and
    direct use of Android Keystore", so `EncryptedSharedPreferences` is out.
  - OkHttp's [`Authenticator`](https://github.com/square/okhttp/blob/master/okhttp/src/commonJvmAndroid/kotlin/okhttp3/Authenticator.kt)
    is the hook for "reactive authentication … the response code is 401". It should
    give up (`return null`) when the request already carried an attempt, counting
    attempts through `priorResponse`. [fact]

## The three options

### (a) Bearer token tied to the `Session` row

Add a second purpose, `generates_token_for :native_api { created_at.to_i }`, to
`Session`. Accept it only for `!service_account?` sessions and only on JSON requests.
Native keeps it in the Keychain / Keystore and sends `Authorization: Bearer`.

- **Shared session:** yes. It's the same row as the webview cookie, so it dies with
  that row. [inference from the token_for and revocation facts]
- **CSRF:** a bearer is never ambient, so writes can skip CSRF only when the token
  resolves. That's the `ServiceAccountAuthentication` pattern already reviewed. The
  route planner's create and update are store v1 writes. [fact for the pattern]
- **Background and extensions:** a Keychain item marked AfterFirstUnlock is readable
  from a background `URLSession` or a widget. The WebKit cookie store isn't shared with
  extensions. [inference]
- **Weakness:** native has to get the token somehow. Sign-in is a Hotwire page
  (ADR 0006), so the first token has to come from the webview's session. One cookie
  read per sign-in, or a token exposed to page JS (rejected below).
- **Testability:** best. A Rails integration test passes a header. A native unit test
  injects a string.

### (b) Reuse the webview cookie in `URLSession` / OkHttp

Read `session_id` from `WKHTTPCookieStore` / `CookieManager` before each request, as
the spike and `FileDownloader` do. On Android an OkHttp `CookieJar` can delegate to
`CookieManager`.

- **Shared session:** perfect by construction. One credential, one store. [fact, spike]
- **CSRF:** cookie-authenticated JSON writes need the format-based CSRF exemption that
  `ActivitiesController` already has. Their safety then rests on `SameSite=Lax` alone.
  Every new write endpoint repeats that decision. [fact for today's exemption; risk is
  inference]
- **Coupling:**
  - Every native request starts with an async hop into WebKit (iOS) or the WebView
    provider (Android).
  - It needs the right host filtering. `WebSessionCookies` implements that by hand.
  - It can't run where the WebKit store isn't available (extensions). [inference]
- **Testability:** fine with a `CookieSource` protocol and a fake. The Rails side needs
  the `login` dance instead of a header. Slightly worse than (a) on both sides. [inference]

### (c) Bridge a native token into the webview cookie stores

Sign in natively (an API returns a token), then plant the session cookie in
`WKHTTPCookieStore.setCookie` / `CookieManager.setCookie`, or load a hidden request
with the bearer header that answers `Set-Cookie` (the Basecamp 3 way).

- It needs native sign-in screens, which ADR 0006 rules out ("auth … stay Hotwire for
  good"). [fact]
- Native can't mint the cookie: it's `cookies.signed`, so the server would have to hand
  back the signed value or set it through a hidden web request. That's two writes to
  keep in sync and a session-injection surface. [inference]
- It's only useful when native is the login entry point. **Rejected for v1.** Keep the
  hidden-request trick in reserve for a token-present-but-cookie-missing case if it
  ever shows up in practice (see Risks).

### Rejected variant: the token in the bridge message

`bridge--authentication` could carry the token in its `connect` payload. That puts a
long-lived bearer into page JS and the DOM, where an XSS can exfiltrate it. The
`httponly` cookie exists to prevent exactly that. The native cookie read is the safer
handoff. [inference]

### Comparison

| | (a) bearer on `Session` | (b) reuse cookie | (c) token → cookie |
|---|---|---|---|
| Fits web-only sign-in (ADR 0006) | yes, via one exchange | yes | no (needs native sign-in) |
| Web sign-out / revocation kills native | yes (same row) | yes | yes, if same row |
| CSRF for native writes | skip when the token resolves | format exemption, Lax only | n/a for writes |
| Works outside the webview's cookie store | yes | no | yes |
| Rails test | header in, status out | `login` + cookie | header + cookie assertions |
| Native unit test | fake `TokenStore` | fake `CookieSource` | fake both + cookie writes |
| New moving parts | exchange endpoint, token store | none | native sign-in, cookie minting |

## Recommendation

### Credential and storage

- **Native holds a `:native_api` bearer token** signed for the same `Session` row as the
  webview cookie. Leave out `expires_in` for v1, which matches the cookie's 20 years
  (see Risks).
- **iOS:** one Keychain generic-password item (service `fr.armandmgt.velo`, account
  `api-token`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
  - Keychain items can outlive an app delete. On first launch (a `UserDefaults` flag
    is missing), delete any leftover item. [inference: widely observed but not stated
    in the Apple docs consulted]
- **Android:** a small app-private DataStore/SharedPreferences entry, encrypted with
  an AES-GCM key from the Android Keystore.
  - If decryption fails (key lost), treat the token as absent.
  - `allowBackup="false"` already keeps it off backups. [fact]
  - Honest caveat: `CookieManager` keeps the equally powerful cookie in app-private
    storage without app-level encryption, so this is defense in depth, not a new
    boundary. [inference]

### Server changes (inputs to #20)

1. **`NativeApiAuthentication` concern** (or generalize `ServiceAccountAuthentication`
   into a purpose-aware bearer concern). It needs:
   - `resume_session`: `super || (request.format.json? && find_session_by_native_token)`,
     accepting only `!service_account?` sessions.
   - `skip_forgery_protection if: -> { native token resolves }`.
   - Bearer is **not** accepted for HTML, so webviews stay cookie-only, mirroring the
     service-account scoping. Keep the service-account purpose and flag check apart.
2. **`request_authentication`**: for `request.format.json?`, skip `return_to` and
   answer `401` with `WWW-Authenticate` (`request_http_token_authentication`, or
   `head :unauthorized` plus a `Bearer` header). HTML keeps `redirect_to new_session_path`.
3. **Exchange endpoint**, e.g. `GET /session.json`. The route `resource :session, only: %i[show …]`
   already exists, but there's no action.
   - Cookie-authenticated. It returns `{ token:, user: { id, … } }` for `Current.session`
     with `Cache-Control: no-store`.
   - Minting is stateless, so a GET needs no CSRF exemption, and a cross-site page
     can't read the JSON. [inference]
   - Add a `rate_limit` like `SessionsController#create`.
   - Refuse bearer-authenticated calls, so a token can't mint tokens.
4. **Once the native client uses bearer**, drop `ActivitiesController`'s `unless:
   request.format.json?` CSRF exemption in favour of (1).

### Flows per platform

**Cold start.**
- **iOS:** if the Keychain has a token, go straight to the tab bar. Native tabs call the
  API, and a 401 is handled below. If there is no token, start the unauthenticated
  navigator at `/session/new` as today. A still-valid cookie redirects to root,
  `bridge--authentication` fires, and that path runs the exchange.
- **Android:** the same with `MainActivity` / `LoginActivity`.
- Users upgrading from today's app have a cookie and no token, so they pass through the
  second path silently. [inference]

**Sign-in (web form).**
1. `POST /session` sets the cookie.
2. The authenticated page mounts `bridge--authentication`.
3. `didSignIn` / `AuthenticationComponent` runs `exchangeToken()`:
   - read the cookie (`WebSessionCookies` on iOS, `CookieManager.getCookie` on Android);
   - call `GET /session.json`;
   - store the token;
   - then swap to the tabs.

   Native screens await a single-flight token task, so a tab that appears first doesn't
   race the exchange.

**Sign-out from the web** (a Hotwire "Déconnexion").
1. `DELETE /session` destroys the row, so the cookie and token are both dead.
2. The redirect to `/session/new` hits `is_after_sign_out_path`.
3. The shell calls `signOutLocally()`: delete the token, clear the host's cookies
   (`WKHTTPCookieStore.delete` / `CookieManager.removeAllCookies` + `flush`), swap to the
   sign-in root.

   Today's `didSignOut()` / `SignOutRouteDecisionHandler` become thin callers of that one
   function.

**Sign-out from native** (if a native screen ever offers it): call `DELETE /session`
with the bearer (one more JSON path for #20), then run `signOutLocally()` either way.

**Expiry.** None in v1. The cookie lasts 20 years, the token has no `expires_in`, and
rows are never pruned. If expiry arrives later as a row sweep, both credentials die
together and the 401 path handles it with no client change. [inference]

**Server-side revocation** (password reset, account deletion, a manual `Session#destroy`):
- **Native request:** `401` → one silent re-exchange with the cookie → that also gets
  `401`, because the cookie's row is gone → `signOutLocally()`.
- **Webview visit:** redirect to `/session/new` → `is_after_sign_out_path` →
  `signOutLocally()`. Both paths end at the same function.

**A web sign-in making native work again** (for example after a sign-out and sign-in in
the webview, while native still holds a dead token): the bridge `connect` re-runs the
exchange and replaces the token. If a native request gets there first, its 401 triggers
the same re-exchange, which now succeeds and retries once. [inference]

**Returning to the sign-in root on 401.** One app-level auth state object owns the
root swap, and the API client only reports to it.
- **iOS:** an `@Observable AuthSession` (or `NotificationCenter` `.didSignOut`, mirroring
  `.didSignIn`) observed by `SceneDelegate`. `APIClient` is an `actor` that
  single-flights the re-exchange and retries at most once.
- **Android:** an OkHttp `Interceptor` adds the header. An `Authenticator` does the
  re-exchange and returns `null` when `priorResponse` already carries an attempt. The
  final 401 goes to an app-scoped `StateFlow<AuthState>` that starts `LoginActivity`
  with `FLAG_ACTIVITY_CLEAR_TASK`, as `SignOutRouteDecisionHandler` already does.

### Testing in the agent loop

- **Rails** (`bin/rails test`, deterministic):
  - bearer on JSON → 200;
  - no credential on JSON → 401 with `WWW-Authenticate` and no `Location`;
  - HTML → still a 302 to `/session/new`;
  - bearer on an HTML request → ignored (302);
  - token after `session.destroy` / password reset → 401;
  - service-account token on the user API → 401, native token on admin → rejected;
  - a native token skips CSRF on a JSON write, but a cookie-only JSON write does not
    (once the exemption is dropped);
  - exchange: cookie → token for `Current.session`, bearer → refused, rate-limited.
  - These extend `test/integration/service_account_auth_test.rb`'s style.
- **iOS** (Swift Testing on the pinned simulator): `APIClient` with an injected
  `TokenStore`, `CookieSource` and a `URLProtocol` stub.
  - Assert the header is attached.
  - 401 → one exchange → retry succeeds.
  - 401 → exchange 401 → `AuthSession` becomes `.signedOut`, with no third request.
  - Concurrent 401s → one exchange.
  - The Keychain wrapper gets a round-trip test (Keychain works in hosted simulator
    tests [inference]).
- **Android** (JUnit / Robolectric on the JVM): the same cases with OkHttp
  `MockWebServer`, a fake `TokenStore` and a `CookieSource` interface wrapping
  `CookieManager`. That keeps the WebView provider out of JVM tests.
- **Maestro** (slow end-to-end layer, both shells, mirrored flows):
  - sign in → native Activités list shows rows;
  - web sign-out → back at `/session/new`;
  - revoke (`bin/rails runner 'Session.destroy_all'` against dev) → pull to refresh on a
    native screen → sign-in root.
- Option (b) would test about as well on native, but needs the cookie `login` dance in
  Rails. Option (c) adds cookie-store writes that only a device run can verify.

## Risks and open items

- **#20 must decide where JSON lives:** `respond_to` beside HTML in the same controllers,
  or an `Api::` namespace. Either way the bearer concern has to sit on it, and bearer
  must stay JSON-only. A namespace makes "bearer only here" a one-line include, like
  `Admin::AdminController`. [inference]
- **#20: unify the error shape.** Whatever the 401 body is, native keys off the status
  code alone. Don't let any JSON action redirect (for example `authorize_admin!`-style
  `redirect_to`).
- **Tokens never expire, and there's no device list.** A leaked token works until its
  row is destroyed, and the user can only do that through a password reset.
  - Follow-ups: a `last_seen_at` touch plus an idle sweep, and a "sessions" page to
    revoke one device.
  - Either keeps both credentials in lockstep, because both resolve the row.
- **The stale `rowid` comment.** The `created_at.to_i` binding in `ServiceAccountSession`
  mentions "a reused SQLite rowid". The app is on Postgres, but the binding is still
  correct; copy it, not the comment.
- **The `Session` row's `user_agent` records the webview**, not the native client, and
  native calls don't update it. That's fine for v1. Revisit if a device list arrives.
- **Token present, cookie missing** (website data cleared or evicted). The webview then
  lands on `/session/new` and the shell signs out fully. That is acceptable. If it
  turns out to be common, add the Basecamp-style recovery: a hidden webview request
  with the bearer to an endpoint that sets the cookie (option c's mechanism). [inference]
- **WebKit cookie timing.** The exchange reads the cookie after the bridge `connect`,
  which fires after the authenticated page rendered. The `Set-Cookie` arrived on the
  `POST /session` response before that redirect, so it should be readable. The spike
  saw it work, but run the Maestro sign-in flow on both platforms after every Hotwire
  bump. [inference + spike fact]
- **Hotwire Native Android 1.2.8 → 1.4.x** changes cookie scoping on the library's own
  requests. It doesn't affect this design, because the API client is separate, but note
  it when bumping. [fact for the change]
- **`allow_browser`.** Set an explicit native API User-Agent and keep a test that it
  isn't blocked. [inference]
- **Push registration** (not built yet) should go through the bearer API and hang off
  the `Session` row (`dependent: :destroy`), so revocation also stops pushes. [inference]
- **`secret_key_base` rotation** signs everyone out on every client at once (cookie and
  token). That's the intended behaviour; mention it in the deploy notes.

## Sources

- Repo (at `607352a`): `app/controllers/concerns/authentication.rb`,
  `app/controllers/concerns/service_account_authentication.rb`,
  `app/models/concerns/service_account_session.rb`, `app/models/session.rb`,
  `app/controllers/{sessions,passwords,users,activities,configurations}_controller.rb`,
  `app/controllers/admin/admin_controller.rb`, `config/routes.rb`,
  `test/integration/service_account_auth_test.rb`, `lib/tasks/service_accounts.rake`,
  `app/javascript/controllers/bridge/{authentication,push_subscription}_controller.js`,
  `native/ios/Sources/{WebSessionCookies,FileDownloader,SceneDelegate}.swift`,
  `native/ios/Sources/Bridge/AuthenticationComponent.swift`,
  `native/android/app/src/main/kotlin/fr/armandmgt/velo/{VeloApplication.kt,main/*.kt,bridge/AuthenticationComponent.kt}`,
  `native/android/app/build.gradle.kts`, `native/android/app/src/main/AndroidManifest.xml`.
- Spike (#8, worktree `prototype-native-mixed-tabs`): `native/ios/Sources/Spike/ActivitiesNativeScreen.swift`,
  `native/android/app/src/main/kotlin/fr/armandmgt/velo/spike/SpikeActivitiesFragment.kt`.
- Rails 8.1.4 gem source: `railties/…/authentication/templates/app/controllers/concerns/authentication.rb.tt`,
  `actionpack/lib/action_controller/metal/http_authentication.rb`,
  `actionpack/lib/action_dispatch/middleware/cookies.rb`,
  `activerecord/lib/active_record/token_for.rb`;
  [`allow_browser.rb`](https://github.com/rails/rails/blob/main/actionpack/lib/action_controller/metal/allow_browser.rb);
  [`ActiveRecord::TokenFor`](https://api.rubyonrails.org/classes/ActiveRecord/TokenFor/ClassMethods.html).
- Hotwire: [turbo-ios Authentication.md](https://github.com/hotwired/turbo-ios/blob/main/Docs/Authentication.md);
  [hotwire-native-ios `HotwireConfig.swift`](https://github.com/hotwired/hotwire-native-ios/blob/main/Source/HotwireConfig.swift);
  [hotwire-native-android 1.4.0 release](https://github.com/hotwired/hotwire-native-android/releases/tag/1.4.0);
  `dev.hotwire:core:1.2.8` POM (Maven Central).
- Apple: [WKHTTPCookieStore](https://developer.apple.com/documentation/webkit/wkhttpcookiestore),
  [WKWebsiteDataStore](https://developer.apple.com/documentation/webkit/wkwebsitedatastore),
  [kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly).
- Android / OkHttp: [CookieManager](https://developer.android.com/reference/android/webkit/CookieManager),
  [androidx.security releases](https://developer.android.com/jetpack/androidx/releases/security),
  [OkHttp `Authenticator`](https://github.com/square/okhttp/blob/master/okhttp/src/commonJvmAndroid/kotlin/okhttp3/Authenticator.kt).
