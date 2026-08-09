# frozen_string_literal: true

module FrontendErrors
  # Renders browser frames as Ruby backtrace lines.
  #
  # Error backends parse backtraces with a Ruby-shaped regex — roughly
  #
  #     /^((?:[a-zA-Z]:)?[^:]+):(\d+)(?::in [`']([^']+)')?$/
  #
  # so a frame written as "/app/javascript/foo.js:42:in `connect'" is understood,
  # linked to its source and (when the path is under the project root) treated as
  # application code. Two constraints follow from that regex: the file part can't
  # contain a colon, and a trailing ":column" makes the whole line fail to match —
  # hence columns are dropped here and carried in the report context instead.
  #
  # Frames we can't resolve to a source file are emitted verbatim; backends fall
  # back to showing the unparsed line, so nothing is lost.
  class BacktraceFormatter
    DEFAULT_METHOD = "<anonymous>"

    def initialize(source_mapper)
      @source_mapper = source_mapper
    end

    # @param frames [Array<StackParser::Frame>]
    # @return [Array<String>]
    def call(frames)
      frames.filter_map { |frame| format_frame(frame) }
    end

    private
      def format_frame(frame)
        return frame.raw if frame.url.nil? || frame.line.nil?

        path = @source_mapper.resolve(frame.url)
        return frame.raw unless path

        "#{path}:#{frame.line}:in `#{frame.function || DEFAULT_METHOD}'"
      end
  end
end
