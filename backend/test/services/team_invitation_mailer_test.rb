require "test_helper"
require "mail"
require "net/smtp"

class TeamInvitationMailerTest < ActiveSupport::TestCase
  class CapturingSmtp < Net::SMTP
    attr_reader :authentication, :messages, :starttls_context
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

    def sendmail(message, sender, recipients)
      raise delivery_error if delivery_error
      @messages << { source: message, sender: sender, recipients: recipients }
    end
  end

  setup do
    @smtp = { "host" => "smtp.example.test", "port" => "587", "username" => "smtp-user",
      "password" => " smtp-password ", "from" => "convites@example.test" }
    @token = SecureRandom.urlsafe_base64(32)
    @options = { email: "equipe@example.test", token: @token,
      origin: "https://app.example.test", smtp: @smtp }
    @connection = CapturingSmtp.new
  end

  def deliver(**options)
    Net::SMTP.stub(:new, @connection) do
      TeamInvitationMailer.deliver!(**@options.merge(options))
    end
  end

  def assert_invalid(**options)
    Net::SMTP.stub(:new, ->(*) { flunk "Invalid input reached the SMTP transport" }) do
      error = assert_raises(ArgumentError) do
        TeamInvitationMailer.deliver!(**@options.merge(options))
      end
      refute_includes error.message, @token
    end
  end

  test "encodes a Portuguese invitation and returns no message or token" do
    logs = StringIO.new
    Rails.stub(:logger, ActiveSupport::Logger.new(logs)) do
      assert_output("", "") { assert_nil deliver }
    end

    envelope = @connection.messages.fetch(0)
    message = Mail.read_from_string(envelope.fetch(:source))
    assert_equal "convites@example.test", envelope.fetch(:sender)
    assert_equal ["equipe@example.test"], envelope.fetch(:recipients)
    assert_equal ["convites@example.test"], message.from
    assert_equal ["equipe@example.test"], message.to
    assert_equal "Convite para sua equipe no Advocacia Online", message.subject
    assert_equal "text/plain", message.mime_type
    assert_equal "UTF-8", message.charset
    body = message.body.decoded.encode(Encoding::UTF_8, message.charset)
    assert body.valid_encoding?
    assert_includes body, "entre com a conta Google de equipe@example.test"
    assert_includes body, "uso único"
    assert_includes body, "24 horas"
    assert_includes body, "https://app.example.test/invite/accept#token=#{@token}"
    refute_includes message.header.to_s, @token
    assert_empty logs.string
  end

  test "uses the configured SMTP endpoint with mandatory STARTTLS authenticated after TLS" do
    endpoint = nil
    Net::SMTP.stub(:new, ->(host, port) { endpoint = [host, port]; @connection }) do
      assert_nil TeamInvitationMailer.deliver!(**@options)
    end

    assert_equal ["smtp.example.test", 587], endpoint
    assert_equal ["app.example.test", "smtp-user", " smtp-password ", :plain], @connection.authentication
    assert @connection.starttls_always?
    refute @connection.starttls_auto?
    refute @connection.tls?
    assert @connection.tls_verify
    assert_equal OpenSSL::SSL::VERIFY_PEER, @connection.starttls_context.verify_mode
    assert @connection.starttls_context.verify_hostname
  end

  test "normalizes a trailing origin slash and percent encodes the token only in the fragment" do
    token = "opaque+token/with?query&part=#value%"
    deliver(origin: "https://app.example.test:8443/", token: token, smtp: @smtp.merge("port" => 2525))

    body = Mail.read_from_string(@connection.messages.fetch(0).fetch(:source)).body.decoded
    link = URI(body.lines.map(&:strip).find { |line| line.start_with?("https://") })
    assert_equal "https", link.scheme
    assert_equal "app.example.test", link.host
    assert_equal 8443, link.port
    assert_equal "/invite/accept", link.path
    assert_nil link.query
    assert_equal({ "token" => token }, URI.decode_www_form(link.fragment).to_h)
    refute_includes link.fragment, "&part="
  end

  test "rejects invalid recipients and header injection before opening SMTP" do
    [nil, 42, "", " ", "not-an-email", "first@example.test,second@example.test",
     "Nome <equipe@example.test>", "equipe@example.test\r\nBcc: other@example.test",
     "josé@example.com", "equipe@exámple.com", "equipe\u0000@example.test", "\xff".b.force_encoding("UTF-8")].each do |email|
      assert_invalid(email: email)
    end
  end

  test "recipient normalization is shared with invitation creation" do
    assert_equal "equipe@example.test", TeamInvitationMailer.normalize_recipient!("  EQUIPE@EXAMPLE.TEST  ")
    assert_raises(ArgumentError) { TeamInvitationMailer.normalize_recipient!("josé@example.com") }
    assert_raises(ArgumentError) { TeamInvitationMailer.normalize_recipient!("equipe@example.test\n") }
  end

  test "rejects blank malformed or multiline tokens without exposing them" do
    [nil, 42, "", " ", "token\nother", "token\u0000", "token with spaces", "a" * 4097,
     "\xff".b.force_encoding("UTF-8")].each do |token|
      assert_invalid(token: token)
    end
  end

  test "requires an HTTPS origin without credentials path query or fragment" do
    [nil, 42, "", "http://app.example.test", "https://", "https://user:secret@app.example.test",
     "https://app.example.test/path", "https://app.example.test?query=secret",
     "https://app.example.test#fragment", "https://app.example.test:0",
     "https://app.example.test:65536", "https://app.example.test\n"].each do |origin|
      assert_invalid(origin: origin)
    end
  end

  test "requires complete SMTP configuration with string keys" do
    [nil, [], {}, @smtp.transform_keys(&:to_sym)].each do |smtp|
      assert_invalid(smtp: smtp)
    end
    @smtp.each_key do |key|
      assert_invalid(smtp: @smtp.except(key))
      [nil, "", "\r\n"].each { |value| assert_invalid(smtp: @smtp.merge(key => value)) }
    end
  end

  test "rejects invalid SMTP endpoint port credentials and sender" do
    { "host" => [42, "smtp://smtp.example.test", "smtp.example.test/path", "smtp.example.test\n"],
      "port" => [0, -1, 65536, 587.5, "587junk", " 587", true],
      "username" => [42, "smtp-user\n"], "password" => [42, "secret\u0000"],
      "from" => [42, "invalid", "first@example.test,second@example.test",
        "convites@example.test\r\nBcc: other@example.test"] }.each do |key, values|
      values.each { |value| assert_invalid(smtp: @smtp.merge(key => value)) }
    end
  end

  test "SMTP authentication TLS timeout and server failures never become success or expose secrets" do
    [Net::SMTPAuthenticationError.new("535 #{@token} #{@smtp.fetch('password')}"),
     Net::SMTPFatalError.new("550 #{@token}"), OpenSSL::SSL::SSLError.new(@token),
     Net::ReadTimeout.new(@token), IOError.new(@token)].each do |failure|
      @connection.delivery_error = failure
      error = assert_raises(TeamInvitationMailer::DeliveryFailed) { deliver }
      assert_equal "Não foi possível enviar o convite por SMTP.", error.message
      assert_nil error.cause
      refute_includes error.full_message, @token
      refute_includes error.full_message, @smtp.fetch("password")
      assert_empty @connection.messages
    end
  end
end
