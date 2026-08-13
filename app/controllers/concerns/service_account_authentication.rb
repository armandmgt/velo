# Bearer-token authentication for service accounts, layered on top of Authentication's
# cookie sessions.
#
# Include this *after* Authentication: the override below relies on sitting ahead of it in
# the ancestor chain, so `super` is the stock cookie lookup and the token is only consulted
# when that finds nothing.
module ServiceAccountAuthentication
  extend ActiveSupport::Concern

  included do
    # CSRF exists to protect requests the browser authenticates automatically via the session
    # cookie. Token auth is never ambient — the client attaches it deliberately — so a request
    # authenticated that way needs no CSRF token. This asks whether the token actually resolves to
    # a service-account session, not merely whether an Authorization header is present: otherwise
    # any bearer-shaped string would exempt a cookie-authenticated write.
    skip_forgery_protection if: -> { find_session_by_token.present? }
  end

  private
    def resume_session
      super || (Current.session = find_session_by_token)
    end

    def find_session_by_token
      authenticate_with_http_token do |token, _options|
        session = Session.find_by_token_for(:service_account_api, token)
        session if session&.service_account?
      end
    end
end
