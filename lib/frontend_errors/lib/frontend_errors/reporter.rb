# frozen_string_literal: true

module FrontendErrors
  # Hands a browser error to Rails' error reporter.
  #
  # Reporting through ActiveSupport::ErrorReporter rather than writing to a
  # specific backend is what keeps this reusable: whatever the host has
  # subscribed — Solid Errors, Sentry, a plain logger — picks browser errors up
  # on the same path as server-side ones, and in an environment with no
  # subscriber at all nothing breaks.
  class Reporter
    def initialize(report, context: {}, source_mapper: SourceMapper.new)
      @report = report
      @context = context
      @source_mapper = source_mapper
    end

    def call
      error = build_error
      log(error) if FrontendErrors.log_reports?

      Rails.error.report(
        error,
        handled: @report.handled?,
        severity: @report.severity,
        source: @report.source,
        context: context
      )
    end

    private
      def build_error
        error = @report.error_class.new(@report.message)
        error.set_backtrace(backtrace)
        error
      end

      def backtrace
        BacktraceFormatter.new(@source_mapper).call(@report.frames)
      end

      # Server-derived context is merged last, so it always wins: whatever a host
      # adds to `allowed_context_keys`, a client must never be able to overwrite
      # the identity we resolved for it.
      def context
        top_frame = @report.frames.first
        @report.context
          .merge(@context)
          .merge(column: top_frame&.column)
          .compact
      end

      def log(error)
        Rails.logger.warn do
          "[frontend_errors] #{error.class.name}: #{error.message} " \
            "(#{@report.source}) #{error.backtrace&.first}"
        end
      end
  end
end
