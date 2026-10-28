require "test_helper"

class OidcAttemptTest < ActiveSupport::TestCase
  test "state is one use and bound to initiating browser" do
    attempt = OidcAttempt.start(bucket: IdentityStore.digest(SecureRandom.uuid))
    assert_nil OidcAttempt.consume(browser: SecureRandom.urlsafe_base64(32), state: attempt.fetch(:state))
    assert_nil OidcAttempt.consume(browser: attempt.fetch(:browser), state: SecureRandom.urlsafe_base64(32))
    payload = OidcAttempt.consume(browser: attempt.fetch(:browser), state: attempt.fetch(:state))
    assert_equal attempt.fetch(:nonce), payload.fetch("nonce")
    assert_equal attempt.fetch(:verifier), payload.fetch("verifier")
    assert_nil OidcAttempt.consume(browser: attempt.fetch(:browser), state: attempt.fetch(:state))
  end

  test "expired encrypted attempt cannot authenticate" do
    attempt = OidcAttempt.start(bucket: IdentityStore.digest(SecureRandom.uuid))
    travel 11.minutes do
      assert_nil OidcAttempt.consume(browser: attempt.fetch(:browser), state: attempt.fetch(:state))
    end
  end

  test "login rate limit is server-side and shared across callers" do
    bucket = IdentityStore.digest(SecureRandom.uuid)
    20.times { assert OidcAttempt.start(bucket: bucket) }
    assert_nil OidcAttempt.start(bucket: bucket)
  end
end
