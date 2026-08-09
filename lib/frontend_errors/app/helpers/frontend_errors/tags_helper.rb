# frozen_string_literal: true

module FrontendErrors
  module TagsHelper
    # Configuration for the browser-side reporter, read by frontend_errors.js.
    # A meta tag rather than an inline script so the module stays a plain,
    # cacheable asset and nothing has to be exempted from a CSP.
    def frontend_errors_tag(**overrides)
      config = {
        endpoint: frontend_errors.reports_path,
        maxReports: FrontendErrors.max_reports_per_page,
        maxMessageLength: FrontendErrors.max_message_length,
        maxFrames: FrontendErrors.max_frames
      }.merge(overrides)

      tag.meta(name: "frontend-errors", content: config.to_json)
    end
  end
end
