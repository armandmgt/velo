# frozen_string_literal: true

module FrontendErrors
  # Turns a browser stack trace string into structured frames.
  #
  # Two dialects have to be handled. V8 (Chrome, Edge, node) prefixes every frame
  # with "at" and puts the location in parentheses when a function name is known:
  #
  #     Error: boom
  #         at Object.connect (https://host/assets/x-abc123.js:42:15)
  #         at https://host/assets/x-abc123.js:1:1
  #         at new Foo (https://host/assets/x-abc123.js:7:9)
  #         at async load (https://host/assets/x-abc123.js:3:1)
  #
  # SpiderMonkey/JavaScriptCore (Firefox, Safari) use "function@location" with no
  # prefix, and an empty function name for top-level frames:
  #
  #     connect@https://host/assets/x-abc123.js:42:15
  #     @https://host/assets/x-abc123.js:1:1
  class StackParser
    Frame = Struct.new(:function, :url, :line, :column, :raw, keyword_init: true)

    # "at fn (url:line:col)" / "at url:line:col". The location group is greedy up
    # to the final two ":n" pairs so that URLs containing colons still split right.
    V8 = /\A\s*at\s+(?:(?<function>.+?)\s+\()?(?<url>.+?):(?<line>\d+):(?<column>\d+)\)?\s*\z/

    # "fn@url:line:col"
    MOZ = /\A\s*(?<function>[^@]*)@(?<url>.+?):(?<line>\d+):(?<column>\d+)\s*\z/

    def self.parse(stack, limit: FrontendErrors.max_frames)
      new(stack).parse(limit: limit)
    end

    def initialize(stack)
      @stack = stack.to_s
    end

    def parse(limit: FrontendErrors.max_frames)
      frames = []

      @stack.each_line do |raw_line|
        line = raw_line.strip
        next if line.empty?

        if (frame = frame_from(line))
          frames << frame
        elsif frames.any?
          # Something we can't decompose but that sits inside the trace, e.g.
          # Safari's "[native code]". Worth keeping verbatim.
          frames << Frame.new(raw: line)
        end
        # Anything unparseable *before* the first frame is the "Name: message"
        # header V8 prepends, which we already have as the message.

        break if frames.size >= limit
      end

      frames
    end

    private
      def frame_from(line)
        match = V8.match(line) || MOZ.match(line)
        return unless match

        Frame.new(
          function: normalize_function(match[:function]),
          url: match[:url],
          line: match[:line].to_i,
          column: match[:column].to_i,
          raw: line.strip
        )
      end

      # "new Foo" and "async load" carry a V8 modifier rather than a name we can
      # show as-is; keep the name and drop the noise.
      def normalize_function(function)
        name = function.to_s.strip
        name = name.delete_prefix("async ").delete_prefix("new ")
        name.empty? ? nil : name
      end
  end
end
