# frozen_string_literal: true

module FrontendErrors
  class ReportsController < FrontendErrors.base_controller_class.constantize
    # navigator.sendBeacon can't set an X-CSRF-Token header, and the beacon path is
    # the one that survives a page being closed — which is exactly when we most
    # want the queued errors. See the class comment below for what guards this
    # instead.
    skip_forgery_protection

    # The endpoint is deliberately reachable without a session, so that errors on
    # the sign-in and sign-up pages are captured too. That makes it publicly
    # writable, so it's bounded on every axis: requests per IP here, body size and
    # report count in #create, message length in MessageNormalizer, and the
    # generated exception-class registry in FrontendErrors.error_class_for.
    rate_limit to: FrontendErrors.rate_limit_to,
               within: FrontendErrors.rate_limit_within,
               name: "frontend_errors"

    def create
      return head(:content_too_large) if request.content_length.to_i > FrontendErrors.max_body_bytes

      source_mapper = SourceMapper.new(host: request.host)

      Payload.parse(request.body.read).each do |report|
        Reporter.new(report, context: report_context, source_mapper: source_mapper).call
      end

      head :no_content
    end

    private
      # No `url` here: the client reports its own `location.href`, which is both
      # more accurate than a Referer taken at flush time and unaffected by
      # Referrer-Policy. Deriving one here would only fight it, since server
      # context takes precedence.
      def report_context
        { user_agent: request.user_agent }.merge(host_context).compact
      end

      # Host-supplied identity/context. Evaluated in the controller so it can read
      # cookies, headers and whatever else the app needs to resolve a user.
      def host_context
        context = instance_exec(&FrontendErrors.context)
        context.is_a?(Hash) ? context : {}
      end
  end
end
