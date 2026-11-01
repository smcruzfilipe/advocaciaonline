require "mail"
require "uri"
require "timeout"

class FirstAccessInvitationMailer
  class DeliveryFailed < StandardError; end
  class DeliveryUnknown < DeliveryFailed; end

  def self.deliver!(email:, link:)
    origin = AppSettings.origin
    settings = TeamInvitationMailer.send(:smtp_settings, AppSettings.smtp)
    message = Mail.new
    message.from = settings.fetch(:from)
    message.to = TeamInvitationMailer.normalize_recipient!(email)
    message.subject = "Convite para primeiro acesso ao Advocacia Online"
    message.content_type = "text/plain; charset=UTF-8"
    message.body = <<~BODY
      Você recebeu um convite para seu primeiro acesso ao Advocacia Online.

      Acesse o link abaixo para iniciar seu cadastro:

      #{link}

      O convite é de uso único e válido por 24 horas a partir da emissão. O reenvio não altera esse prazo.
      Se você não esperava este convite, ignore esta mensagem.
    BODY
    # Direct transport avoids global Mail callbacks that could log the invitation.
    Mail::SMTP.new(settings.except(:from).merge(domain: URI(origin).host)).deliver!(message)
    nil
  rescue Timeout::Error, Errno::ETIMEDOUT, IO::TimeoutError
    raise DeliveryUnknown, "O resultado do envio por SMTP é desconhecido.", cause: nil
  rescue StandardError
    raise DeliveryFailed, "Não foi possível enviar o convite por SMTP.", cause: nil
  end
end
