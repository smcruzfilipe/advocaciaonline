require "mail"

class VerificationMailer
  class DeliveryFailed < StandardError; end

  def self.deliver!(email:, token:)
    origin = AppSettings.origin
    smtp = AppSettings.smtp
    # Reuse the invitation transport's strict validation and mandatory STARTTLS.
    settings = TeamInvitationMailer.send(:smtp_settings, smtp)
    message = Mail.new
    message.from = settings.fetch(:from)
    message.to = TeamInvitationMailer.normalize_recipient!(email)
    message.subject = "Confirme seu e-mail no Advocacia Online"
    message.content_type = "text/plain; charset=UTF-8"
    message.body = "Confirme seu e-mail acessando o link de uso único, válido por 24 horas:\n\n#{origin}/verify-email#token=#{token}\n\nSe você não solicitou o cadastro, ignore esta mensagem.\n"
    Mail::SMTP.new(settings.except(:from).merge(domain: URI(origin).host)).deliver!(message)
  rescue StandardError
    raise DeliveryFailed, "Não foi possível enviar o e-mail de confirmação.", cause: nil
  end
end
