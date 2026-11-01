require "openssl"
require "base64"
require "uri"
require "active_support/security_utils"
require "digest"
require "json"

class PasswordAuthentication
  ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".freeze
  DUMMY_HASH = "scrypt$" + Base64.strict_encode64("\0" * 16) + "$" + Base64.strict_encode64("\0" * 32)

  def self.password_hash(password)
    salt = SecureRandom.random_bytes(16)
    "scrypt$#{Base64.strict_encode64(salt)}$#{Base64.strict_encode64(derive(password, salt))}"
  end

  def self.valid_password?(password, stored)
    algorithm, salt, expected = (stored || DUMMY_HASH).split("$", 3)
    return false unless algorithm == "scrypt" && salt && expected
    salt = Base64.strict_decode64(salt)
    expected = Base64.strict_decode64(expected)
    return false unless salt.bytesize == 16 && expected.bytesize == 32
    ActiveSupport::SecurityUtils.secure_compare(derive(password, salt), expected)
  rescue ArgumentError
    false
  end

  def self.derive(password, salt)
    OpenSSL::KDF.scrypt(password, salt: salt, N: 16384, r: 8, p: 1, length: 32)
  end
  private_class_method :derive

  def self.new_secret
    bits = SecureRandom.random_bytes(20).unpack1("B*")
    bits.scan(/.{5}/).map { |chunk| ALPHABET[chunk.to_i(2)] }.join
  end

  def self.encrypt(secret)
    encryptor.encrypt_and_sign(secret)
  end

  def self.decrypt(ciphertext)
    encryptor.decrypt_and_verify(ciphertext)
  end

  def self.encryptor
    key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key("password-totp-encryption-v1", 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm")
  end
  private_class_method :encryptor

  def self.code(secret, step)
    bits = secret.chars.map { |char| ALPHABET.index(char).to_i.to_s(2).rjust(5, "0") }.join
    key = [bits].pack("B*")
    digest = OpenSSL::HMAC.digest("SHA1", key, [step].pack("Q>"))
    offset = digest.getbyte(-1) & 15
    number = digest.byteslice(offset, 4).unpack1("N") & 0x7fffffff
    (number % 1_000_000).to_s.rjust(6, "0")
  end

  def self.matching_step(secret, candidate, now: Time.now.to_i)
    return unless candidate.is_a?(String) && candidate.match?(/\A[0-9]{6}\z/)
    current = now / 30
    [current - 1, current, current + 1].find do |step|
      ActiveSupport::SecurityUtils.secure_compare(code(secret, step), candidate)
    end
  end

  def self.uri(email, secret)
    label = URI.encode_www_form_component("Advocacia Online:#{email}").gsub("+", "%20")
    "otpauth://totp/#{label}?#{URI.encode_www_form(secret: secret, issuer: 'Advocacia Online', algorithm: 'SHA1', digits: 6, period: 30)}"
  end

  # Each independently generated code has 256 bits of entropy; SHA-256 is
  # appropriate for lookup because these are not human-chosen passwords.
  def self.new_recovery_codes
    Array.new(10) { SecureRandom.urlsafe_base64(32) }
  end

  def self.recovery_code_hash(code)
    Digest::SHA256.hexdigest(code)
  end

  def self.begin_platform_recovery(email:, password:, recovery_code:)
    return unless email.is_a?(String) && password.is_a?(String) &&
      recovery_code.is_a?(String) && recovery_code.match?(/\A[A-Za-z0-9_-]{43}\z/)
    if ApplicationRecord.connection.transaction_open?
      raise ActiveRecord::ActiveRecordError, "Recovery requires a top-level transaction"
    end
    row = IdentityStore.call("password_lookup", email)
    valid = valid_password?(password, row && row.fetch("password_hash"))
    return unless row && valid
    secret = new_secret
    token = SecureRandom.urlsafe_base64(32)
    result = platform_recovery_query("platform_recovery_begin", email, row.fetch("password_hash"),
      recovery_code_hash(recovery_code), IdentityStore.digest(token), encrypt(secret))
    return unless result && [true, "t"].include?(result.fetch("started"))
    { challenge: token, secret: secret, otpauth_uri: uri(email, secret) }
  end

  def self.confirm_platform_recovery(challenge:, code:)
    return unless challenge.is_a?(String) && challenge.match?(/\A[A-Za-z0-9_-]{43}\z/)
    connection = ApplicationRecord.connection
    raise ActiveRecord::ActiveRecordError, "Recovery confirmation requires a top-level transaction" if connection.transaction_open?
    row = platform_recovery_query("platform_recovery_secret", IdentityStore.digest(challenge))
    return unless row
    encrypted_secret = row.fetch("totp_secret")
    step = matching_step(decrypt(encrypted_secret), code)
    return unless step
    codes = new_recovery_codes
    hashes = codes.map { |value| recovery_code_hash(value) }
    result = platform_recovery_query("platform_recovery_finish", IdentityStore.digest(challenge),
      encrypted_secret, step.to_s, JSON.generate(hashes))
    codes if result && [true, "t"].include?(result.fetch("changed"))
  end

  def self.platform_recovery_query(function, *values)
    connection = ApplicationRecord.connection
    DatabaseContext.assert_runtime!(connection)
    placeholders = values.each_index.map { |index| "$#{index + 1}::text" }.join(", ")
    connection.raw_connection.exec_params("SELECT * FROM app_private.#{function}(#{placeholders})", values).first
  end
  private_class_method :platform_recovery_query
end
