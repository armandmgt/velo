# frozen_string_literal: true

require "test_helper"

class ErrorClassTest < Minitest::Test
  def setup
    FrontendErrors.reset_error_classes!
  end

  def teardown
    FrontendErrors.reset_error_classes!
  end

  def test_names_the_class_after_the_javascript_error
    klass = FrontendErrors.error_class_for("TypeError")

    assert_equal "JS::TypeError", klass.name
    assert_operator klass, :<, FrontendErrors::BrowserError
    assert_equal "boom", klass.new("boom").message
  end

  def test_memoizes_so_grouping_stays_stable
    assert_same FrontendErrors.error_class_for("TypeError"), FrontendErrors.error_class_for("TypeError")
  end

  # The name comes from the client, so anything that isn't a plain identifier has
  # to collapse rather than become a class of its own.
  def test_rejects_names_that_are_not_identifiers
    [ "not a class", "Type-Error", "typeError", "", nil, "A" * 100, "Type<script>" ].each do |name|
      assert_equal "JS::Error", FrontendErrors.error_class_for(name).name, name.inspect
    end
  end

  def test_caps_the_registry
    (FrontendErrors::MAX_ERROR_CLASSES + 10).times { |i| FrontendErrors.error_class_for("Error#{i}") }

    assert_equal FrontendErrors::BrowserError, FrontendErrors.error_class_for("SomethingElse")
  end
end
