# frozen_string_literal: true

require "active_support"
require "active_support/core_ext/module/attribute_accessors"
require "active_support/core_ext/numeric/bytes"
require "active_support/core_ext/numeric/time"

require "frontend_errors/version"

module FrontendErrors
  # Base class for every error reported from the browser. Concrete classes are
  # built per JavaScript error name by .error_class_for.
  class BrowserError < StandardError; end

  # JavaScript error names we're willing to turn into a Ruby class name. Anything
  # else (including anything an attacker could POST) collapses to JS::Error.
  NAME_PATTERN = /\A[A-Z][A-Za-z0-9_]{0,63}\z/

  # Upper bound on the generated class registry, so a hostile client can't grow it
  # without limit.
  MAX_ERROR_CLASSES = 100

  # Controller the ingest endpoint inherits from. Deliberately not the host's
  # ApplicationController by default: the endpoint must stay reachable without a
  # session (errors on the sign-in page matter too), and it shouldn't pick up
  # whatever before_actions the host installs. Identity comes from `context`.
  mattr_accessor :base_controller_class, default: "::ActionController::Base"

  # Lambda instance_exec'd in the controller, returning a flat hash of extra
  # context (user id, native flag, ...). It has access to `request`, `cookies`
  # and anything else the controller exposes. Not subject to
  # `allowed_context_keys` — that governs client input, this is server-derived.
  mattr_accessor :context, default: -> { {} }

  # Client-supplied context keys we're willing to store. An allowlist rather than
  # a denylist because the payload is unauthenticated: add the keys your own
  # instrumentation sends, and nothing else gets through. Values are still
  # constrained to short scalars regardless of what's listed here.
  mattr_accessor :allowed_context_keys, default: %w[url referrer viewport identifier frame_id method status]

  # Per-IP rate limit on the ingest endpoint.
  mattr_accessor :rate_limit_to, default: 30
  mattr_accessor :rate_limit_within, default: 1.minute

  # Hard caps. Everything below is attacker-controlled, and `message` in particular
  # feeds the error fingerprint of whichever backend records the report.
  mattr_accessor :max_body_bytes, default: 64.kilobytes
  mattr_accessor :max_reports_per_request, default: 20
  mattr_accessor :max_message_length, default: 500
  mattr_accessor :max_frames, default: 30

  # Budget the browser gives itself per page view, so one error in a loop can't
  # turn into a flood of requests. Reset on each Turbo visit.
  mattr_accessor :max_reports_per_page, default: 10

  # Substitutions applied to messages before reporting. Error backends commonly
  # fingerprint on the message, so anything that varies per occurrence (ids, urls,
  # digests) would otherwise split one bug across many groups.
  mattr_accessor :message_filters, default: [
    [ /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i, "<uuid>" ],
    [ /\bblob:\S+/i, "<blob-url>" ],
    [ %r{\bhttps?://\S+}i, "<url>" ],
    [ /\b[0-9a-f]{16,}\b/i, "<hash>" ]
  ]

  # Whether to log every report. nil means "decide from the environment": on
  # outside production, where there's usually no ErrorReporter subscriber
  # installed and the log is the only way to see the pipeline work.
  mattr_accessor :log_reports, default: nil

  class << self
    def log_reports?
      return log_reports unless log_reports.nil?

      defined?(Rails) && Rails.respond_to?(:env) && !Rails.env.production?
    end

    # Builds (and memoizes) an exception class whose #name reads "JS::TypeError".
    # Error backends key their grouping off the exception class name, so this is
    # what makes browser errors legible next to server-side ones.
    def error_class_for(js_name)
      name = NAME_PATTERN.match?(js_name.to_s) ? js_name.to_s : "Error"

      error_classes_lock.synchronize do
        error_classes[name] ||=
          if error_classes.size >= MAX_ERROR_CLASSES
            BrowserError
          else
            Class.new(BrowserError) do
              define_singleton_method(:name) { "JS::#{name}" }
            end
          end
      end
    end

    def reset_error_classes! # :nodoc: for tests
      error_classes_lock.synchronize { @error_classes = {} }
    end

    private
      def error_classes
        @error_classes ||= {}
      end

      def error_classes_lock
        @error_classes_lock ||= Mutex.new
      end
  end
end

require "frontend_errors/message_normalizer"
require "frontend_errors/stack_parser"
require "frontend_errors/source_mapper"
require "frontend_errors/backtrace_formatter"
require "frontend_errors/report"
require "frontend_errors/payload"
require "frontend_errors/reporter"
require "frontend_errors/engine" if defined?(Rails::Engine)
