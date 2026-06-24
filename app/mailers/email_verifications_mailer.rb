class EmailVerificationsMailer < ApplicationMailer
  def verify(user)
    @user = user
    @token = user.generate_token_for(:email_verification)
    mail subject: "Confirmez votre adresse email", to: user.email_address
  end
end
