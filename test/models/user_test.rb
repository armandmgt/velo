require "test_helper"

class UserTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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

  test "email_verified? reflects email_verified_at" do
    assert users(:one).email_verified?
    assert_not users(:unverified).email_verified?
  end

  test "verify_email! sets email_verified_at" do
    user = users(:unverified)
    assert_changes -> { user.email_verified? }, from: false, to: true do
      user.verify_email!
    end
  end

  test "email_verification token round-trips" do
    user = users(:unverified)
    token = user.generate_token_for(:email_verification)
    assert_equal user, User.find_by_token_for(:email_verification, token)
  end

  test "email_verification token is invalidated when the email address changes" do
    user = users(:unverified)
    token = user.generate_token_for(:email_verification)
    user.update!(email_address: "changed@example.com")
    assert_nil User.find_by_token_for(:email_verification, token)
  end

  test "email_verification token expires" do
    user = users(:unverified)
    token = user.generate_token_for(:email_verification)
    travel 2.days do
      assert_nil User.find_by_token_for(:email_verification, token)
    end
  end

  test "changing max HR enqueues a recompute of every effort score" do
    user = users(:one)

    assert_enqueued_with(job: RecomputeEffortScoresJob, args: [ user ]) do
      user.update!(max_heart_rate: 190)
    end
  end

  test "saving without changing max HR enqueues nothing" do
    user = users(:one)

    assert_no_enqueued_jobs(only: RecomputeEffortScoresJob) do
      user.update!(name: "Armand")
    end
  end
end
