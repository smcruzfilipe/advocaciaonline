require "test_helper"
require "mail"
require "net/smtp"

class FirstAccessInvitationMailerTest < ActiveSupport::TestCase
  class CapturingSmtp < Net::SMTP
    attr_reader :messages, :authentication, :starttls_context
    attr_accessor :delivery_error

    def initialize
      super("smtp.example.test", 587)
      @messages = []
    end

    def enable_starttls(context = nil)
      @starttls_context = context
      super
    end

    def start(*authentication)
      @authentication = authentication
      yield self
    end

    def sendmail(source, sender, recipients)
      raise delivery_error if delivery_error
      @messages << { source: source, sender: sender, recipients: recipients }
    end
  end

  setup do
    @smtp = { "host" => "smtp.example.test", "port" => 587, "username" => "smtp-user",
      "password" => "smtp-password", "from" => "convites@example.test" }
    @token = SecureRandom.urlsafe_base64(32)
    @link = "#{AppSettings.origin}/primeiro-acesso#token=#{@token}"
    @connection = CapturingSmtp.new
  end

  test "sends the supplied first access link to the normalized recipient over verified STARTTLS" do
    endpoint = nil
    logs = StringIO.new
    Rails.stub(:logger, ActiveSupport::Logger.new(logs)) do
      AppSettings.stub(:smtp, @smtp) do
        Net::SMTP.stub(:new, ->(host, port) { endpoint = [host, port]; @connection }) do
          assert_nil FirstAccessInvitationMailer.deliver!(email: "  ADVOGADO@EXAMPLE.TEST  ", link: @link)
        end
      end
    end
    envelope = @connection.messages.fetch(0)
    message = Mail.read_from_string(envelope.fetch(:source))
    assert_equal ["smtp.example.test", 587], endpoint
    assert_equal [URI(AppSettings.origin).host, "smtp-user", "smtp-password", :plain], @connection.authentication
    assert @connection.starttls_always?
    refute @connection.starttls_auto?
    assert @connection.tls_verify
    assert_equal OpenSSL::SSL::VERIFY_PEER, @connection.starttls_context.verify_mode
    assert @connection.starttls_context.verify_hostname
    assert_equal "convites@example.test", envelope.fetch(:sender)
    assert_equal ["advogado@example.test"], envelope.fetch(:recipients)
    assert_equal ["advogado@example.test"], message.to
    assert_equal "multipart/alternative", message.mime_type
    assert_includes message.text_part.decoded, @link
    assert_includes message.text_part.decoded, "24 horas"
    action = Nokogiri::HTML(message.html_part.decoded).css("a").find { |anchor| anchor.text.strip == "Iniciar meu cadastro" }
    assert_not_nil action
    assert_equal @link, action["href"]
    refute_includes message.header.to_s, @token
    assert_empty logs.string
  end

  test "transport errors and configuration errors are safe and timeouts have an unknown result" do
    [Net::SMTPAuthenticationError.new("535 #{@token} smtp-password"),
     Net::SMTPFatalError.new("550 #{@token}"), OpenSSL::SSL::SSLError.new(@token),
     IOError.new(@token), Net::ReadTimeout.new(@token), Errno::ETIMEDOUT.new(@token), IO::TimeoutError.new(@token)].each do |failure|
      @connection.delivery_error = failure
      AppSettings.stub(:smtp, @smtp) do
        Net::SMTP.stub(:new, @connection) do
          error = assert_raises(FirstAccessInvitationMailer::DeliveryFailed) do
            FirstAccessInvitationMailer.deliver!(email: "advogado@example.test", link: @link)
          end
          assert_equal failure.is_a?(Timeout::Error) || failure.is_a?(Errno::ETIMEDOUT) || failure.is_a?(IO::TimeoutError),
            error.is_a?(FirstAccessInvitationMailer::DeliveryUnknown)
          assert_nil error.cause
          refute_includes error.full_message, @token
          refute_includes error.full_message, "smtp-password"
        end
      end
    end
    AppSettings.stub(:smtp, -> { raise KeyError, "smtp-password #{@token}" }) do
      error = assert_raises(FirstAccessInvitationMailer::DeliveryFailed) do
        FirstAccessInvitationMailer.deliver!(email: "advogado@example.test", link: @link)
      end
      assert_nil error.cause
      refute_includes error.full_message, @token
      refute_includes error.full_message, "smtp-password"
    end
  end
end
