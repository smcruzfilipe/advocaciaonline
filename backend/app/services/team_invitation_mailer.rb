require "mail"
require "uri"

class TeamInvitationMailer
  class DeliveryFailed < StandardError; end

  class << self
    def deliver!(email:, token:, origin:, smtp:)
      email = normalize_recipient!(email)
      url = invitation_url(token: token, origin: origin)
      settings = smtp_settings(smtp)

      message = Mail.new
      message.from = settings.fetch(:from)
      message.to = email
      message.subject = "Convite para sua equipe no Advocacia Online"
      message.content_type = "text/plain; charset=UTF-8"
      message.body = <<~BODY
        Você recebeu um convite para integrar uma equipe no Advocacia Online.

        Para aceitar, acesse o link abaixo e entre com a conta Google de #{email}:

        #{url}

        Este convite é de uso único e expira em até 24 horas. A revogação ou o vencimento da credencial pode invalidá-lo antes desse prazo.
        Se você não esperava este convite, ignore esta mensagem.
      BODY

      # Direct transport avoids global Mail callbacks that could log the invitation.
      # https://github.com/mikel/mail/blob/2.9.1/lib/mail/network/delivery_methods/smtp.rb
      begin
        Mail::SMTP.new(settings.except(:from).merge(domain: URI(origin).host)).deliver!(message)
      rescue StandardError
        # SMTP responses may echo message content; never expose their text or cause.
        raise DeliveryFailed, "Não foi possível enviar o convite por SMTP.", cause: nil
      end
      nil
    end

    def normalize_recipient!(value)
      raise ArgumentError, "Endereço de e-mail inválido." unless single_line_string?(value)
      address = value.strip.downcase
      validate_address!(address)
      address
    end

    private

    def single_line_string?(value)
      value.is_a?(String) && value.valid_encoding? && value.encoding.ascii_compatible? &&
        !value.strip.empty? && !value.match?(/[[:cntrl:]]/)
    end

    def validate_address!(value)
      unless single_line_string?(value) && value.ascii_only? && value.bytesize <= 254 &&
          value.match?(URI::MailTo::EMAIL_REGEXP)
        raise ArgumentError, "Endereço de e-mail inválido."
      end
    end

    def invitation_url(token:, origin:)
      unless single_line_string?(token) && token.ascii_only? && token.bytesize <= 4096 &&
          !token.match?(/[[:space:]]/)
        raise ArgumentError, "Token de convite inválido."
      end
      unless single_line_string?(origin) && origin.ascii_only?
        raise ArgumentError, "Origem HTTPS inválida."
      end

      uri = URI(origin)
      unless uri.is_a?(URI::HTTPS) && uri.host && !uri.host.empty? && uri.userinfo.nil? &&
          uri.query.nil? && uri.fragment.nil? && ["", "/"].include?(uri.path) && uri.port.between?(1, 65535)
        raise ArgumentError, "Origem HTTPS inválida."
      end
      # Fragments are not sent in HTTP requests or access logs; acceptance uses POST.
      "#{origin.delete_suffix('/')}/invite/accept##{URI.encode_www_form(token: token)}"
    rescue URI::Error
      raise ArgumentError, "Origem HTTPS inválida.", cause: nil
    end

    def smtp_settings(smtp)
      unless smtp.is_a?(Hash) && smtp.keys.all? { |key| key.is_a?(String) } &&
          %w[host username password from].all? { |key| single_line_string?(smtp[key]) }
        raise ArgumentError, "Configuração SMTP inválida."
      end
      validate_address!(smtp.fetch("from"))
      host = smtp.fetch("host")
      unless host.ascii_only? && !host.match?(/[[:space:]]/)
        raise ArgumentError, "Servidor SMTP inválido."
      end
      host = URI::Generic.build(host: host).hostname

      port = smtp["port"]
      unless port.is_a?(Integer) || (single_line_string?(port) && port.ascii_only? && port.match?(/\A[0-9]+\z/))
        raise ArgumentError, "Porta SMTP inválida."
      end
      port = port.to_i
      raise ArgumentError, "Porta SMTP inválida." unless port.between?(1, 65535)

      # Require STARTTLS rather than the opportunistic default; keep certificate verification defaults.
      # https://github.com/ruby/net-smtp/blob/v0.5.2/lib/net/smtp.rb
      { address: host, port: port, user_name: smtp.fetch("username"), password: smtp.fetch("password"),
        from: smtp.fetch("from"), authentication: :plain, enable_starttls: :always }
    rescue URI::Error
      raise ArgumentError, "Servidor SMTP inválido.", cause: nil
    end
  end
end
