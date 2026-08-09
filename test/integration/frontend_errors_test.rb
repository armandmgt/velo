require "test_helper"

class FrontendErrorsTest < ActionDispatch::IntegrationTest
  # A stack as Chrome actually emits it, pointing at real assets so the Propshaft
  # digest reversal has something to resolve.
  STACK = <<~STACK
    TypeError: Cannot read properties of null (reading 'connect')
        at Object.connect (http://www.example.com/assets/controllers/map_controller-abc12345.js:42:15)
        at http://www.example.com/assets/application-def67890.js:1:1
        at https://cdn.example.com/widget.js:9:1
  STACK

  test "reports a browser error through Rails.error" do
    report = assert_error_reported(FrontendErrors::BrowserError) do
      post_reports [ {
        name: "TypeError",
        message: "Cannot read properties of null (reading 'connect')",
        stack: STACK,
        source: "window"
      } ]
    end

    assert_response :no_content
    assert_equal "JS::TypeError", report.error.class.name
    assert_equal "Cannot read properties of null (reading 'connect')", report.error.message
    assert_equal "javascript.window", report.source
    assert_equal :error, report.severity
    refute_predicate report, :handled?
  end

  test "rewrites frames of our own assets into ruby backtrace lines" do
    report = assert_error_reported(FrontendErrors::BrowserError) do
      post_reports [ { name: "TypeError", message: "boom", stack: STACK, source: "window" } ]
    end

    backtrace = report.error.backtrace

    assert_equal "#{Rails.root.join("app/javascript/controllers/map_controller.js")}:42:in `Object.connect'",
                 backtrace.first
    assert_equal "#{Rails.root.join("app/javascript/application.js")}:1:in `<anonymous>'", backtrace.second
    # Not one of ours, so there's nothing to resolve it to — kept verbatim.
    assert_equal "at https://cdn.example.com/widget.js:9:1", backtrace.third
  end

  test "attaches the signed-in user and page context" do
    user = users(:one)
    login user

    report = assert_error_reported(FrontendErrors::BrowserError) do
      post_reports [ {
        message: "boom",
        source: "stimulus",
        stack: "    at connect (http://www.example.com/assets/application-def67890.js:3:7)",
        context: { url: "http://www.example.com/activities", identifier: "map" }
      } ]
    end

    assert_equal user.id, report.context[:user_id]
    assert_equal "map", report.context[:identifier]
    assert_equal "http://www.example.com/activities", report.context[:url]
    assert_equal 7, report.context[:column]
    assert_equal false, report.context[:native]
  end

  # The allowlist is configurable, so a host could add a key that collides with
  # something the server resolves itself. Server-derived context has to win, or a
  # client could attribute its errors to another user.
  test "client context cannot overwrite server-derived context" do
    login users(:one)

    report = with_allowed_context_keys(FrontendErrors.allowed_context_keys + %w[user_id native]) do
      assert_error_reported(FrontendErrors::BrowserError) do
        post_reports [ { message: "boom", context: { user_id: users(:two).id, native: true } } ]
      end
    end

    assert_equal users(:one).id, report.context[:user_id]
    assert_equal false, report.context[:native]
  end

  # Solid Errors fingerprints on source and severity as well as class and
  # message, so the capture site has to survive the round trip for a Turbo
  # failure not to group with an identically-worded uncaught exception.
  test "labels the capture site" do
    reports = capture_error_reports(FrontendErrors::BrowserError) do
      post_reports [
        { name: "TypeError", message: "boom", source: "window" },
        { name: "TurboFrameMissing", message: "boom", source: "turbo" }
      ]
    end

    assert_equal [ "javascript.window", "javascript.turbo" ], reports.map(&:source)
    assert_equal [ :error, :warning ], reports.map(&:severity)
    assert_equal [ false, true ], reports.map(&:handled?)
  end

  test "does not require a session" do
    assert_error_reported(FrontendErrors::BrowserError) do
      post_reports [ { name: "Error", message: "boom on the sign-in page", source: "window" } ]
    end

    assert_response :no_content
    assert_nil capture_error_reports(FrontendErrors::BrowserError) { }.first
  end

  test "refuses an oversized body" do
    assert_no_error_reported do
      post_reports [ { message: "x" * 100_000 } ]
    end

    assert_response :content_too_large
  end

  test "accepts garbage without reporting anything" do
    assert_no_error_reported do
      post frontend_errors.reports_path, params: "not json",
           headers: { "CONTENT_TYPE" => "application/json" }
    end

    assert_response :no_content
  end

  test "drops reports with nothing to say" do
    assert_no_error_reported do
      post_reports [ { message: "   " }, {} ]
    end

    assert_response :no_content
  end

  private
    def with_allowed_context_keys(keys)
      original = FrontendErrors.allowed_context_keys
      FrontendErrors.allowed_context_keys = keys
      yield
    ensure
      FrontendErrors.allowed_context_keys = original
    end

    def post_reports(reports)
      post frontend_errors.reports_path,
           params: { reports: reports }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }
    end
end
