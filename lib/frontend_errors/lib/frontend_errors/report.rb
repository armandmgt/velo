# frozen_string_literal: true

module FrontendErrors
  # One browser error, normalised into everything needed to report it.
  #
  # Every field here arrives from the client, so nothing is passed through
  # untouched: the capture site picks the reported source and severity (rather
  # than the payload naming them), extra context is allowlisted, and the message
  # is normalised and truncated.
  class Report
    # Capture site => [reported source, severity, handled]. The source ends up in
    # the fingerprint, so this both labels the report and keeps, say, a Turbo
    # failure from grouping with an identically-worded uncaught exception.
    CAPTURE_SITES = {
      "window" => [ "javascript.window", :error, false ],
      "promise" => [ "javascript.promise", :error, false ],
      "stimulus" => [ "javascript.stimulus", :error, false ],
      "turbo" => [ "javascript.turbo", :warning, true ]
    }.freeze

    DEFAULT_CAPTURE_SITE = [ "javascript", :error, false ].freeze

    # Values are kept flat and short whatever FrontendErrors.allowed_context_keys
    # permits: backends render context as a plain key/value list, and the payload
    # is unauthenticated.
    MAX_CONTEXT_VALUE_LENGTH = 200

    attr_reader :name, :message, :stack, :source, :severity, :context

    def self.from(attributes)
      attributes = attributes.to_h { |key, value| [ key.to_s, value ] }

      # A blank message would be dropped (or worse, raise) by backends that
      # require one, so fall back to the error name before giving up.
      message = MessageNormalizer.call(attributes["message"])
      message = MessageNormalizer.call(attributes["name"]) if message.empty?
      return nil if message.empty?

      new(
        name: attributes["name"],
        message: message,
        stack: attributes["stack"],
        capture_site: attributes["source"],
        context: attributes["context"]
      )
    end

    def initialize(name:, message:, stack:, capture_site:, context: nil)
      @name = name
      @message = message
      @stack = stack
      @source, @severity, @handled = CAPTURE_SITES.fetch(capture_site.to_s, DEFAULT_CAPTURE_SITE)
      @context = sanitize_context(context)
    end

    def handled? = @handled

    def error_class = FrontendErrors.error_class_for(name)

    def frames
      @frames ||= StackParser.parse(stack)
    end

    private
      def sanitize_context(context)
        return {} unless context.respond_to?(:each_pair)

        # Hosts configure the allowlist with whichever of strings or symbols come
        # naturally; compare on strings.
        allowed = FrontendErrors.allowed_context_keys.map(&:to_s)

        context.each_pair.with_object({}) do |(key, value), result|
          key = key.to_s
          next unless allowed.include?(key)
          next unless scalar?(value)

          result[key.to_sym] = value.is_a?(String) ? value.strip[0, MAX_CONTEXT_VALUE_LENGTH] : value
        end
      end

      def scalar?(value)
        case value
        when String, Numeric, TrueClass, FalseClass then true
        else false
        end
      end
  end
end
