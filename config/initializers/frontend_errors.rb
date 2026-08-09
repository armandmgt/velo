# frozen_string_literal: true

# Extra context attached to every browser error report.
#
# The ingest controller inherits ActionController::Base rather than
# ApplicationController — the endpoint has to stay reachable without a session so
# that errors on the sign-in and sign-up pages are captured — which means the
# Authentication concern never runs and Current.user isn't populated. Resolve the
# session from the cookie directly instead.
FrontendErrors.context = -> {
  session_id = cookies.signed[:session_id]
  session = Session.find_by(id: session_id) if session_id

  {
    user_id: session&.user_id,
    session_id: session&.id,
    native: hotwire_native_app?
  }
}
