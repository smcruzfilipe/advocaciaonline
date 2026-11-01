require "test_helper"

class PasswordAuthenticationTest < ActiveSupport::TestCase
  test "scrypt salts passwords and rejects incorrect values" do
    first = PasswordAuthentication.password_hash("long password one")
    second = PasswordAuthentication.password_hash("long password one")
    refute_equal first, second
    refute_includes first, "long password one"
    assert PasswordAuthentication.valid_password?("long password one", first)
    refute PasswordAuthentication.valid_password?("long password two", first)
    refute PasswordAuthentication.valid_password?("long password one", nil)
  end

  test "TOTP implements RFC 6238 SHA1 vectors with six digit truncation" do
    secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
    assert_equal "287082", PasswordAuthentication.code(secret, 59 / 30)
    assert_equal "081804", PasswordAuthentication.code(secret, 1_111_111_109 / 30)
    assert_equal 1, PasswordAuthentication.matching_step(secret, "287082", now: 59)
    assert_nil PasswordAuthentication.matching_step(secret, "287082", now: 120)
  end

  test "TOTP secret is encrypted and authenticated at rest" do
    secret = PasswordAuthentication.new_secret
    ciphertext = PasswordAuthentication.encrypt(secret)
    refute_includes ciphertext, secret
    assert_equal secret, PasswordAuthentication.decrypt(ciphertext)
    assert_raises(ActiveSupport::MessageEncryptor::InvalidMessage) { PasswordAuthentication.decrypt(ciphertext + "x") }
  end

  test "rate limits are shared in the database" do
    bucket = IdentityStore.digest(SecureRandom.uuid)
    20.times { assert IdentityStore.call("auth_limit", bucket).fetch("accepted") }
    refute IdentityStore.call("auth_limit", bucket).fetch("accepted")
  end
end
