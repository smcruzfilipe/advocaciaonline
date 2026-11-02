require "mail"
require "uri"

class PasswordResetMailer
  class DeliveryFailed < StandardError; end

  def self.deliver!(email:, token:)
    unless token.is_a?(String) && token.match?(/\A[A-Za-z0-9_-]{43}\z/)
      raise DeliveryFailed, "Não foi possível enviar as instruções."
    end
    url = "#{AppSettings.origin}/reset-password#token=#{token}"
    deliver_message!(email: email, subject: "Redefinição de senha no Advocacia Online",
      title: "Redefinição de senha", action_label: "Definir nova senha", action_url: url, body: <<~BODY)
      Recebemos uma solicitação de redefinição de senha para este endereço.

      Se você possui uma conta confirmada no Advocacia Online, escolha uma nova senha pelo link de uso único, válido por 30 minutos:

      #{url}

      Uma nova solicitação invalida o link anterior. O autenticador continua obrigatório e não será redefinido.
      Se você não solicitou esta alteração, ignore esta mensagem. Sua senha não será alterada sem a confirmação pelo link.
    BODY
  end

  def self.deliver_changed!(email:)
    origin = AppSettings.origin
    deliver_message!(email: email, subject: "Sua senha foi alterada no Advocacia Online",
      title: "Confirmação de alteração de senha", status: "Senha alterada",
      action_label: "Ir para o login", action_url: "#{origin}/login", body: <<~BODY)
      A senha da sua conta no Advocacia Online foi alterada.

      Todas as sessões e tentativas de login pendentes foram encerradas. Seu autenticador foi preservado e continua obrigatório.
      Se você não reconhece esta alteração, solicite uma nova redefinição de senha em #{origin}/reset-password e entre em contato com o suporte.
    BODY
  end

  def self.deliver_message!(email:, subject:, body:, title:, action_label:, action_url:, status: nil)
    origin = AppSettings.origin
    settings = TeamInvitationMailer.send(:smtp_settings, AppSettings.smtp)
    message = Mail.new
    message.from = settings.fetch(:from)
    message.to = TeamInvitationMailer.normalize_recipient!(email)
    message.subject = subject
    EmailTemplate.apply(message, text: body, title: title, action_label: action_label,
      action_url: action_url, status: status)
    Mail::SMTP.new(settings.except(:from).merge(domain: URI(origin).host)).deliver!(message)
    nil
  rescue StandardError
    raise DeliveryFailed, "Não foi possível enviar o e-mail de redefinição de senha.", cause: nil
  end
  private_class_method :deliver_message!
end
