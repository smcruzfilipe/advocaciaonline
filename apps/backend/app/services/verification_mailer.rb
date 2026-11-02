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
    url = "#{origin}/verify-email#token=#{token}"
    text = "Confirme seu e-mail acessando o link de uso único, válido por 24 horas:\n\n#{url}\n\nSe você não solicitou o cadastro, ignore esta mensagem.\n"
    EmailTemplate.apply(message, text: text, title: "Confirme seu e-mail",
      action_label: "Confirmar meu e-mail", action_url: url)
    Mail::SMTP.new(settings.except(:from).merge(domain: URI(origin).host)).deliver!(message)
  rescue StandardError
    raise DeliveryFailed, "Não foi possível enviar o e-mail de confirmação.", cause: nil
  end
end
