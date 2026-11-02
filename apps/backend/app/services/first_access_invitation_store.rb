class FirstAccessInvitationStore
  TOKEN = /\A[A-Za-z0-9_-]{43}\z/
  PURPOSE = "first-access-link-v1".freeze
  METADATA = %w[id email created_at expires_at].freeze

  def self.list(token:)
    IdentityStore.call_all("first_access_admin_list", IdentityStore.digest(token)).map { |row| row.slice(*METADATA) }
  end

  def self.issue(token:, email:)
    require_top_level_transaction!
    begin
      email = TeamInvitationMailer.normalize_recipient!(email)
    rescue ArgumentError
      raise IdentityStore::InvalidInput, "Invalid invitation recipient", cause: nil
    end
    bearer = SecureRandom.urlsafe_base64(32)
    row = IdentityStore.call("first_access_admin_issue", IdentityStore.digest(token), email,
      IdentityStore.digest(bearer), encryptor.encrypt_and_sign(bearer, purpose: PURPOSE))
    row.slice(*METADATA)
  end

  def self.link(token:, id:)
    require_top_level_transaction!
    validate_id!(id)
    row = IdentityStore.call("first_access_admin_link", IdentityStore.digest(token), id)
    raise IdentityStore::NotFound, "Resource unavailable" unless row
    begin
      bearer = encryptor.decrypt_and_verify(row.fetch("token_ciphertext"), purpose: PURPOSE)
    rescue ActiveSupport::MessageEncryptor::InvalidMessage
      raise IdentityStore::NotFound, "Resource unavailable", cause: nil
    end
    unless valid_token?(bearer) && ActiveSupport::SecurityUtils.secure_compare(IdentityStore.digest(bearer), row.fetch("token_hash"))
      raise IdentityStore::NotFound, "Resource unavailable"
    end
    { link: "#{AppSettings.origin}/primeiro-acesso#token=#{bearer}", expires_at: row.fetch("expires_at") }
  end

  def self.reissue(token:, id:)
    require_top_level_transaction!
    validate_id!(id)
    bearer = SecureRandom.urlsafe_base64(32)
    row = IdentityStore.call("first_access_admin_reissue", IdentityStore.digest(token), id,
      IdentityStore.digest(bearer), encryptor.encrypt_and_sign(bearer, purpose: PURPOSE))
    raise IdentityStore::NotFound, "Resource unavailable" unless row
    row.slice(*METADATA)
  end

  def self.inspect_token(bearer:)
    validate_token!(bearer)
    IdentityStore.call("first_access_inspect", IdentityStore.digest(bearer)) ||
      raise(IdentityStore::NotFound, "Resource unavailable")
  end

  def self.prepare(bearer:, password:, confirmation:)
    validate_token!(bearer)
    unless password.is_a?(String) && password.valid_encoding? && password.length.between?(12, 128) &&
        password.bytesize <= 512 && password == confirmation
      raise IdentityStore::InvalidInput, "Invalid password"
    end
    challenge = SecureRandom.urlsafe_base64(32)
    secret = PasswordAuthentication.new_secret
    row = IdentityStore.call("first_access_prepare", IdentityStore.digest(bearer), IdentityStore.digest(challenge),
      PasswordAuthentication.password_hash(password), PasswordAuthentication.encrypt(secret))
    raise IdentityStore::NotFound, "Resource unavailable" unless row
    { challenge: challenge, secret: secret, otpauth_uri: PasswordAuthentication.uri(row.fetch("email"), secret),
      expires_at: row.fetch("expires_at") }
  end

  def self.prepared(bearer:, challenge:)
    validate_token!(bearer)
    validate_token!(challenge)
    IdentityStore.call("first_access_prepared", IdentityStore.digest(bearer), IdentityStore.digest(challenge)) ||
      raise(IdentityStore::NotFound, "Resource unavailable")
  end

  def self.consume(bearer:, session:)
    validate_token!(bearer)
    IdentityStore.call("first_access_consume", IdentityStore.digest(bearer), IdentityStore.digest(session)) ||
      raise(IdentityStore::NotFound, "Resource unavailable")
  end

  def self.finish(bearer:, challenge:, code:, session:)
    require_top_level_transaction!
    pending = prepared(bearer: bearer, challenge: challenge)
    secret = PasswordAuthentication.decrypt(pending.fetch("totp_secret"))
    step = PasswordAuthentication.matching_step(secret, code)
    raise IdentityStore::NotFound, "Resource unavailable" unless step
    token = SecureRandom.urlsafe_base64(32)
    csrf = SecureRandom.urlsafe_base64(32)
    result = IdentityStore.call("first_access_finish", IdentityStore.digest(bearer), IdentityStore.digest(challenge),
      pending.fetch("totp_secret"), step.to_s, IdentityStore.digest(token), csrf,
      session.present? ? IdentityStore.digest(session) : "")
    raise IdentityStore::NotFound, "Resource unavailable" unless result&.fetch("created")
    token
  end

  def self.valid_token?(value)
    value.is_a?(String) && value.valid_encoding? && value.ascii_only? && TOKEN.match?(value)
  end
  private_class_method :valid_token?

  def self.validate_token!(value)
    raise IdentityStore::NotFound, "Resource unavailable" unless valid_token?(value)
  end
  private_class_method :validate_token!

  def self.validate_id!(value)
    raise IdentityStore::InvalidInput, "Invalid invitation" unless value.is_a?(String) && IdentityStore::UUID.match?(value)
  end
  private_class_method :validate_id!

  def self.require_top_level_transaction!
    if ApplicationRecord.connection.transaction_open?
      raise ActiveRecord::ActiveRecordError, "Invitation operation requires a top-level transaction"
    end
  end
  private_class_method :require_top_level_transaction!

  def self.encryptor
    key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key("first-access-link-encryption-v1", 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm")
  end
  private_class_method :encryptor
end
