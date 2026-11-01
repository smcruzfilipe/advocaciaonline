require "openssl"
require "base64"
require "uri"
require "active_support/security_utils"

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
end
