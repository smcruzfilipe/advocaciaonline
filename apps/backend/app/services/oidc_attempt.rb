class OidcAttempt
  PURPOSE = "google-oidc-attempt".freeze

  def self.start(bucket:)
    browser = SecureRandom.urlsafe_base64(32)
    state = SecureRandom.urlsafe_base64(32)
    nonce = SecureRandom.urlsafe_base64(32)
    verifier = SecureRandom.urlsafe_base64(32)
    payload = encryptor.encrypt_and_sign({ nonce: nonce, verifier: verifier }, purpose: PURPOSE, expires_in: 10.minutes)
    result = IdentityStore.call("start_login", IdentityStore.digest(browser), IdentityStore.digest(state), payload, bucket)
    return unless result.fetch("accepted")
    { browser: browser, state: state, nonce: nonce, verifier: verifier }
  end

  def self.consume(browser:, state:)
    return unless browser.is_a?(String) && state.is_a?(String) &&
      browser.match?(/\A[A-Za-z0-9_-]{43}\z/) && state.match?(/\A[A-Za-z0-9_-]{43}\z/)
    result = IdentityStore.call("consume_login", IdentityStore.digest(browser), IdentityStore.digest(state))
    return unless result
    encryptor.decrypt_and_verify(result.fetch("encrypted_payload"), purpose: PURPOSE)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  def self.encryptor
    key = Rails.application.key_generator.generate_key(PURPOSE, 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm", serializer: :json)
  end
  private_class_method :encryptor
end
