require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "max_heart_rate allows nil" do
    user = users(:one)
    user.max_heart_rate = nil
    assert user.valid?
  end

  test "max_heart_rate accepts a value in range" do
    user = users(:one)
    user.max_heart_rate = 190
    assert user.valid?
  end

  test "max_heart_rate rejects out-of-range and non-integer values" do
    user = users(:one)

    user.max_heart_rate = 80
    assert_not user.valid?

    user.max_heart_rate = 300
    assert_not user.valid?
  end
end
