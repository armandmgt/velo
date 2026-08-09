# frozen_string_literal: true

require "test_helper"

class MessageNormalizerTest < Minitest::Test
  # The point of normalising: backends fingerprint on the message, so two
  # occurrences of one bug have to produce identical text.
  def test_collapses_values_that_vary_between_occurrences
    first = FrontendErrors::MessageNormalizer.call(
      "Failed to load https://velo.test/activities/12?token=abc for 3f2504e0-4f89-11d3-9a0c-0305e82c3301"
    )
    second = FrontendErrors::MessageNormalizer.call(
      "Failed to load https://velo.test/activities/98?token=xyz for 7c9e6679-7425-40de-944b-e07fc1f90ae7"
    )

    assert_equal first, second
    assert_equal "Failed to load <url> for <uuid>", first
  end

  def test_collapses_digests_and_blob_urls
    assert_equal "asset <hash> missing", FrontendErrors::MessageNormalizer.call("asset a1b2c3d4e5f60718 missing")
    assert_equal "cannot decode <blob-url>", FrontendErrors::MessageNormalizer.call("cannot decode blob:https://velo.test/9f8e")
  end

  def test_squeezes_whitespace
    assert_equal "a b c", FrontendErrors::MessageNormalizer.call("  a\n\tb   c ")
  end

  def test_truncates
    assert_equal "zzzz…", FrontendErrors::MessageNormalizer.call("z" * 100, limit: 5)
  end

  def test_handles_nil
    assert_equal "", FrontendErrors::MessageNormalizer.call(nil)
  end
end
