require "test_helper"

class EmailVerificationsMailerTest < ActionMailer::TestCase
  test "verify" do
    user = users(:unverified)
    mail = EmailVerificationsMailer.verify(user)

    assert_equal "Confirmez votre adresse email", mail.subject
    assert_equal [ user.email_address ], mail.to
    assert_equal [ "noreply@amgt.fr" ], mail.from

    assert_match %r{/email_verification\?token=}, mail.body.encoded
  end
end
