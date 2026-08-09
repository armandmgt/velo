# frozen_string_literal: true

require "test_helper"

class BacktraceFormatterTest < Minitest::Test
  # Copied verbatim from SolidErrors::BacktraceLine::INPUT_FORMAT. Producing lines
  # this understands is the whole point of the formatter, so a drift on either
  # side should fail here rather than silently degrade the dashboard to unparsed
  # text.
  SOLID_ERRORS_INPUT_FORMAT = %r{^((?:[a-zA-Z]:)?[^:]+):(\d+)(?::in [`']([^']+)')?$}

  # Stands in for the Propshaft lookup: everything under /assets/ maps to a source
  # file, everything else is unresolvable.
  class StubMapper
    def resolve(url)
      "/rails/app/javascript/controllers/map_controller.js" if url.to_s.include?("/assets/")
    end
  end

  def setup
    @formatter = FrontendErrors::BacktraceFormatter.new(StubMapper.new)
  end

  def test_resolved_frames_are_ruby_shaped
    frames = FrontendErrors::StackParser.parse(
      "    at connect (https://velo.test/assets/controllers/map_controller-abc12345.js:42:15)"
    )

    line = @formatter.call(frames).sole

    assert_equal "/rails/app/javascript/controllers/map_controller.js:42:in `connect'", line
  end

  def test_output_is_parseable_by_the_backend
    frames = FrontendErrors::StackParser.parse(<<~STACK)
          at Object.connect (https://velo.test/assets/controllers/map_controller-abc12345.js:42:15)
          at https://velo.test/assets/application-def67890.js:1:1
    STACK

    @formatter.call(frames).each do |line|
      match = SOLID_ERRORS_INPUT_FORMAT.match(line)

      refute_nil match, "#{line.inspect} is not a parseable backtrace line"
      assert_equal "/rails/app/javascript/controllers/map_controller.js", match[1]
    end
  end

  def test_anonymous_frames_get_a_method_name
    frames = FrontendErrors::StackParser.parse("    at https://velo.test/assets/application-def67890.js:1:1")

    assert_equal "/rails/app/javascript/controllers/map_controller.js:1:in `<anonymous>'",
                 @formatter.call(frames).sole
  end

  def test_unresolvable_frames_pass_through_verbatim
    frames = FrontendErrors::StackParser.parse(<<~STACK)
          at handler (https://cdn.example.com/widget.js:9:1)
      [native code]
    STACK

    assert_equal [ "at handler (https://cdn.example.com/widget.js:9:1)", "[native code]" ],
                 @formatter.call(frames)
  end
end
