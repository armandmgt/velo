class EmailVerificationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Veuillez réessayer plus tard." }

  def show
    if (user = User.find_by_token_for(:email_verification, params[:token]))
      user.verify_email!
      redirect_to new_session_path, notice: "Votre adresse email a été confirmée. Vous pouvez maintenant vous connecter."
    else
      redirect_to new_session_path, alert: "Le lien de confirmation est invalide ou a expiré."
    end
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    redirect_to new_session_path, alert: "Le lien de confirmation est invalide ou a expiré."
  end

  def create
    user = User.find_by(email_address: params[:email_address])
    if user && !user.email_verified?
      EmailVerificationsMailer.verify(user).deliver_later
    end

    redirect_to new_session_path, notice: "Si un compte non confirmé existe pour cette adresse email, un nouveau lien de confirmation a été envoyé."
  end
end
