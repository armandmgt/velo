# frozen_string_literal: true

require "test_helper"

class StackParserTest < Minitest::Test
  def test_parses_v8_frames
    stack = <<~STACK
      TypeError: Cannot read properties of null (reading 'foo')
          at Object.connect (https://velo.test/assets/controllers/map_controller-abc12345.js:42:15)
          at https://velo.test/assets/application-def67890.js:1:1
    STACK

    frames = FrontendErrors::StackParser.parse(stack)

    assert_equal 2, frames.size
    assert_equal "Object.connect", frames[0].function
    assert_equal "https://velo.test/assets/controllers/map_controller-abc12345.js", frames[0].url
    assert_equal 42, frames[0].line
    assert_equal 15, frames[0].column
    assert_nil frames[1].function
    assert_equal 1, frames[1].line
  end

  def test_strips_v8_modifiers
    frames = FrontendErrors::StackParser.parse(<<~STACK)
          at new Foo (https://velo.test/assets/a-1234567.js:7:9)
          at async load (https://velo.test/assets/a-1234567.js:3:1)
    STACK

    assert_equal %w[Foo load], frames.map(&:function)
  end

  def test_parses_firefox_and_safari_frames
    frames = FrontendErrors::StackParser.parse(<<~STACK)
      connect@https://velo.test/assets/controllers/map_controller-abc12345.js:42:15
      @https://velo.test/assets/application-def67890.js:1:1
    STACK

    assert_equal "connect", frames[0].function
    assert_equal 42, frames[0].line
    assert_nil frames[1].function
    assert_equal "https://velo.test/assets/application-def67890.js", frames[1].url
  end

  # A URL with a port has colons of its own; the location split has to happen at
  # the last two ":n" pairs, not the first.
  def test_handles_urls_with_a_port
    frames = FrontendErrors::StackParser.parse("    at connect (http://localhost:3000/assets/a-1234567.js:42:15)")

    assert_equal "http://localhost:3000/assets/a-1234567.js", frames[0].url
    assert_equal 42, frames[0].line
    assert_equal 15, frames[0].column
  end

  def test_drops_the_header_but_keeps_unparseable_frames_inside_the_trace
    frames = FrontendErrors::StackParser.parse(<<~STACK)
      Error: boom
          at connect (https://velo.test/assets/a-1234567.js:42:15)
      [native code]
    STACK

    assert_equal 2, frames.size
    assert_equal "[native code]", frames[1].raw
    assert_nil frames[1].url
  end

  def test_respects_the_frame_limit
    stack = Array.new(50) { |i| "    at f#{i} (https://velo.test/assets/a-1234567.js:#{i}:1)" }.join("\n")

    assert_equal 5, FrontendErrors::StackParser.parse(stack, limit: 5).size
  end

  def test_handles_a_blank_stack
    assert_empty FrontendErrors::StackParser.parse(nil)
    assert_empty FrontendErrors::StackParser.parse("")
  end
end
