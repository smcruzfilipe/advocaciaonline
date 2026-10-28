class SessionsController < ApplicationController
  def show
    context = authenticated_context
    unless context
      cookies.delete(SESSION_COOKIE, **cookie_options(expires: Time.at(0))) if cookies[SESSION_COOKIE]
      return render json: { authenticated: false, onboarded: false }
    end
    render json: { authenticated: true, onboarded: context.fetch("tenant_id").present?, csrf_token: context.fetch("csrf_token") }
  end
end
