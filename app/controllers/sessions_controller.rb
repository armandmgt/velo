class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Veuillez réessayer plus tard." }

  def new
    redirect_to after_authentication_url if find_session_by_cookie.present?
  end

  def create
    if (user = User.authenticate_by(params.expect(user: [ :email_address, :password ])))
      if user.email_verified?
        start_new_session_for user
        redirect_to after_authentication_url
      else
        EmailVerificationsMailer.verify(user).deliver_later
        redirect_to new_session_path, alert: "Confirmez votre adresse email avant de vous connecter. Un nouveau lien de confirmation vient de vous être envoyé."
      end
    else
      redirect_to new_session_path, alert: "Adresse email ou mot de passe incorrect."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
