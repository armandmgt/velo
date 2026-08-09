# frozen_string_literal: true

require "json"

module FrontendErrors
  # Parses the request body into Reports.
  #
  # This is the trust boundary: the endpoint is unauthenticated by design (errors
  # on the sign-in page are worth having), so malformed or hostile input has to
  # produce an empty list rather than an exception.
  module Payload
    def self.parse(body, limit: FrontendErrors.max_reports_per_request)
      parsed = JSON.parse(body.to_s)
      return [] unless parsed.is_a?(Hash)

      reports = parsed["reports"]
      return [] unless reports.is_a?(Array)

      reports.first(limit).filter_map do |attributes|
        Report.from(attributes) if attributes.is_a?(Hash)
      end
    rescue JSON::ParserError
      []
    end
  end
end
