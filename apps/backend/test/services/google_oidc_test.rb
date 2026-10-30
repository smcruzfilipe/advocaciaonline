require "test_helper"

class GoogleOidcTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
    @key = OpenSSL::PKey::RSA.generate(2048)
    @jwk = JWT::JWK.new(@key, kid: "google-test-key", use: "sig", alg: "RS256")
    @client = GoogleOidc.new
    @nonce = SecureRandom.urlsafe_base64(32)
  end

  def claims
    { "iss" => GoogleOidc::ISSUER, "sub" => "google-subject", "aud" => AppSettings.google_client_id,
      "iat" => Time.now.to_i, "exp" => Time.now.to_i + 300, "nonce" => @nonce,
      "email" => "verified@example.test", "email_verified" => true }
  end

  def signed(payload, key: @key, algorithm: "RS256")
    JWT.encode(payload, key, algorithm, kid: "google-test-key")
  end

  def verify(token, nonce: @nonce)
    @client.stub(:request_json, { "keys" => [@jwk.export.transform_keys(&:to_s)] }) do
      @client.verify_id_token(token, nonce: nonce)
    end
  end

  test "accepts verified Google identity and both documented issuer forms" do
    assert_equal({ subject: "google-subject", email: "verified@example.test" }, verify(signed(claims)))
    assert_equal "google-subject", verify(signed(claims.merge("iss" => "accounts.google.com"))).fetch(:subject)
  end

  test "rejects signatures algorithms issuer audience nonce expiry and unverified email" do
    [signed(claims, key: OpenSSL::PKey::RSA.generate(2048)),
     signed(claims, key: nil, algorithm: "none"),
     signed(claims.merge("iss" => "https://attacker.test")),
     signed(claims.merge("aud" => "another-client")),
     signed(claims.merge("exp" => Time.now.to_i)),
     signed(claims.merge("iat" => Time.now.to_i + 120)),
     signed(claims.merge("nonce" => "wrong")),
     signed(claims.merge("email_verified" => false)),
     signed(claims.merge("email_verified" => "true")),
     signed(claims.except("exp")), signed(claims.except("nonce")),
     signed(claims.merge("sub" => "")), signed(claims.merge("email" => "not-an-email"))].each do |token|
      assert_raises(GoogleOidc::AuthenticationFailed) { verify(token) }
    end
  end

  test "multiple audiences require correct authorized party" do
    payload = claims.merge("aud" => [AppSettings.google_client_id, "other"])
    assert_raises(GoogleOidc::AuthenticationFailed) { verify(signed(payload)) }
    assert_raises(GoogleOidc::AuthenticationFailed) { verify(signed(payload.merge("azp" => "other"))) }
    assert_equal "google-subject", verify(signed(payload.merge("azp" => AppSettings.google_client_id))).fetch(:subject)
  end

  test "authorization uses PKCE S256 and configured callback instead of client redirect" do
    verifier = SecureRandom.urlsafe_base64(32)
    uri = URI(@client.authorization_url(state: "state", nonce: @nonce, verifier: verifier))
    query = URI.decode_www_form(uri.query).to_h
    assert_equal GoogleOidc::AUTHORIZATION_ENDPOINT, "#{uri.scheme}://#{uri.host}#{uri.path}"
    assert_equal "code", query.fetch("response_type")
    assert_equal "S256", query.fetch("code_challenge_method")
    assert_equal Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false), query.fetch("code_challenge")
    assert_equal "#{AppSettings.origin}/auth/google/callback", query.fetch("redirect_uri")
  end
end
