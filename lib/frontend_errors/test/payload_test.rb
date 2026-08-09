# frozen_string_literal: true

require "test_helper"

class PayloadTest < Minitest::Test
  def test_builds_reports
    reports = parse(reports: [ {
      name: "TypeError",
      message: "Cannot read properties of null",
      stack: "    at connect (https://velo.test/assets/a-1234567.js:42:15)",
      source: "stimulus",
      context: { url: "https://velo.test/activities", identifier: "map" }
    } ])

    report = reports.sole

    assert_equal "Cannot read properties of null", report.message
    assert_equal "javascript.stimulus", report.source
    assert_equal :error, report.severity
    refute_predicate report, :handled?
    assert_equal({ url: "https://velo.test/activities", identifier: "map" }, report.context)
    assert_equal "JS::TypeError", report.error_class.name
  end

  def test_turbo_reports_are_handled_warnings
    report = parse(reports: [ { name: "TurboFrameMissing", message: "missing", source: "turbo" } ]).sole

    assert_equal :warning, report.severity
    assert_predicate report, :handled?
    assert_equal "javascript.turbo", report.source
  end

  def test_unknown_capture_site_falls_back
    report = parse(reports: [ { name: "Error", message: "boom", source: "../../etc/passwd" } ]).sole

    assert_equal "javascript", report.source
    assert_equal :error, report.severity
  end

  def test_caps_the_number_of_reports
    payload = { reports: Array.new(50) { { name: "Error", message: "boom" } } }

    assert_equal 3, FrontendErrors::Payload.parse(payload.to_json, limit: 3).size
  end

  # A backend that validates message presence would raise from inside the error
  # reporter, so a report with nothing to say has to be dropped here.
  def test_drops_reports_without_a_message
    assert_empty parse(reports: [ { message: "  " } ])
    assert_empty parse(reports: [ {} ])
  end

  def test_falls_back_to_the_error_name_when_the_message_is_blank
    assert_equal "TypeError", parse(reports: [ { name: "TypeError", message: "" } ]).sole.message
  end

  def test_ignores_unknown_context_keys_and_non_scalar_values
    report = parse(reports: [ {
      message: "boom",
      context: { url: "/x", admin: true, nested: { a: 1 }, viewport: %w[a b] }
    } ]).sole

    assert_equal({ url: "/x" }, report.context)
  end

  def test_the_context_allowlist_is_configurable
    with_allowed_context_keys(%w[activity_id]) do
      report = parse(reports: [ { message: "boom", context: { activity_id: 7, url: "/x" } } ]).sole

      assert_equal({ activity_id: 7 }, report.context)
    end
  end

  # Hosts will reach for whichever of strings or symbols reads naturally.
  def test_the_allowlist_accepts_symbols
    with_allowed_context_keys(%i[activity_id]) do
      assert_equal({ activity_id: 7 },
                   parse(reports: [ { message: "boom", context: { activity_id: 7 } } ]).sole.context)
    end
  end

  # Whatever a host allowlists, values stay short scalars — the payload is
  # unauthenticated.
  def test_allowlisted_values_are_still_bounded
    with_allowed_context_keys(%w[note nested]) do
      report = parse(reports: [ {
        message: "boom",
        context: { note: "x" * 1_000, nested: { a: 1 } }
      } ]).sole

      assert_equal FrontendErrors::Report::MAX_CONTEXT_VALUE_LENGTH, report.context[:note].length
      refute_includes report.context, :nested
    end
  end

  def test_survives_garbage
    assert_empty FrontendErrors::Payload.parse("not json")
    assert_empty FrontendErrors::Payload.parse("[]")
    assert_empty FrontendErrors::Payload.parse(nil)
    assert_empty parse(reports: "nope")
    assert_empty parse(reports: [ "nope", 1 ])
  end

  private
    def parse(payload)
      FrontendErrors::Payload.parse(payload.to_json)
    end

    def with_allowed_context_keys(keys)
      original = FrontendErrors.allowed_context_keys
      FrontendErrors.allowed_context_keys = keys
      yield
    ensure
      FrontendErrors.allowed_context_keys = original
    end
end
