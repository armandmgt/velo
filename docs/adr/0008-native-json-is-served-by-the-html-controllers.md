# Native JSON is served by the HTML controllers

The native screens from [ADR 0006](0006-core-screens-are-native.md) read and write
through `format.json` branches on the same controllers that render the web pages
(`/activities/:id.json`, `/best_efforts/:id/removal.json`, …), not through an
`/api/v1` namespace. One controller per resource keeps the web and the apps on the
same actions, scopes and validations, so a rule changed for the web can't drift
from the apps. The cost is that auth depends on the request format instead of
living in one bearer-only base class.

## Consequences worth knowing

- `Authentication` resolves a `:native_api` bearer on JSON requests only and skips
  CSRF just for those. JSON without a bearer falls back to the cookie with CSRF
  enforced, so the web's own fetches keep working. A bearer on HTML is ignored.
  Unauthenticated JSON gets a 401 with `WWW-Authenticate: Bearer`, never a redirect.
- Every action the apps call has an explicit JSON branch. A guard raises in dev
  and test when a JSON response redirects, so a forgotten branch fails in CI.
- The JSON carries no version marker. Changes are additive. A field or endpoint is
  removed only once `MINIMUM_NATIVE_BUILD` is past every build that reads it, and
  older builds get a 426. The same minimum retires old path configurations
  ([ADR 0007](0007-native-screens-navigate-through-hotwire.md)). If a real fork is
  ever needed, it would be a vendor media type, not a URL prefix.
