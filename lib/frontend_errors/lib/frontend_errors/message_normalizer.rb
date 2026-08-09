# frozen_string_literal: true

module FrontendErrors
  # Collapses the parts of a message that vary between occurrences of the same bug.
  #
  # Error backends typically fingerprint on the message (Solid Errors hashes
  # exception class + message + severity + source), so an id, a URL or a digest
  # inside the text would split one recurring bug into an unbounded number of
  # groups. Normalising first keeps one bug to one row.
  class MessageNormalizer
    def self.call(message, filters: FrontendErrors.message_filters, limit: FrontendErrors.max_message_length)
      new(filters: filters, limit: limit).call(message)
    end

    def initialize(filters: FrontendErrors.message_filters, limit: FrontendErrors.max_message_length)
      @filters = filters
      @limit = limit
    end

    def call(message)
      text = message.to_s.strip.gsub(/\s+/, " ")
      text = @filters.reduce(text) { |result, (pattern, replacement)| result.gsub(pattern, replacement) }
      truncate(text)
    end

    private
      def truncate(text)
        return text if text.length <= @limit

        "#{text[0, @limit - 1]}…"
      end
  end
end
