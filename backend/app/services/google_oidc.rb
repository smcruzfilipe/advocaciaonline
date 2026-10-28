require "net/http"
require "jwt"
require "openssl"
require "json"
require "base64"

class GoogleOidc
  class AuthenticationFailed < StandardError; end
  AUTHORIZATION_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth".freeze
  TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token".freeze
  JWKS_ENDPOINT = "https://www.googleapis.com/oauth2/v3/certs".freeze
  ISSUER = "https://accounts.google.com".freeze

  def authorization_url(state:, nonce:, verifier:)
    query = URI.encode_www_form(client_id: AppSettings.google_client_id, response_type: "code",
      scope: "openid email", redirect_uri: callback_url, state: state, nonce: nonce,
      code_challenge: Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false),
      code_challenge_method: "S256")
    "#{AUTHORIZATION_ENDPOINT}?#{query}"
  end

  def exchange(code:, nonce:, verifier:)
    raise AuthenticationFailed unless code.is_a?(String) && code.present? && code.bytesize <= 4096
    response = request_json(TOKEN_ENDPOINT, form: {
      code: code, client_id: AppSettings.google_client_id, client_secret: AppSettings.google_client_secret,
      redirect_uri: callback_url, grant_type: "authorization_code", code_verifier: verifier
    })
    verify_id_token(response.fetch("id_token"), nonce: nonce)
  rescue KeyError
    raise AuthenticationFailed
  end

  def verify_id_token(token, nonce:)
    raise AuthenticationFailed unless token.is_a?(String) && token.bytesize <= 16384
    claims, header = JWT.decode(token, nil, true, {
      algorithms: ["RS256"], jwks: method(:verification_keys),
      iss: [ISSUER, "accounts.google.com"], verify_iss: true,
      aud: AppSettings.google_client_id, verify_aud: true, verify_iat: true,
      verify_expiration: true, verify_not_before: true,
      required_claims: %w[iss sub aud exp iat nonce email email_verified]
    })
    raise AuthenticationFailed if header["crit"].present?
    raise AuthenticationFailed unless claims["email_verified"] == true
    raise AuthenticationFailed unless claims["sub"].is_a?(String) && claims["sub"].length.between?(1, 255)
    raise AuthenticationFailed unless claims["email"].is_a?(String) && claims["email"].match?(URI::MailTo::EMAIL_REGEXP)
    raise AuthenticationFailed unless claims["exp"].is_a?(Numeric) && claims["iat"].is_a?(Numeric)
    received_nonce = claims["nonce"]
    unless received_nonce.is_a?(String) && nonce.is_a?(String) &&
        ActiveSupport::SecurityUtils.secure_compare(received_nonce, nonce)
      raise AuthenticationFailed
    end
    audience = claims["aud"]
    unless audience.is_a?(String) || (audience.is_a?(Array) && audience.all? { |value| value.is_a?(String) })
      raise AuthenticationFailed
    end
    if claims.key?("azp") || (audience.is_a?(Array) && audience.length > 1)
      raise AuthenticationFailed unless claims["azp"] == AppSettings.google_client_id
    end
    { subject: claims.fetch("sub"), email: claims.fetch("email") }
  rescue JWT::DecodeError, JWT::JWKError, ArgumentError, TypeError
    raise AuthenticationFailed
  end

  private

  def callback_url
    "#{AppSettings.origin}/auth/google/callback"
  end

  # The gem calls again with kid_not_found on rotation. A short grace interval
  # prevents arbitrary token headers from turning cache invalidation into a DoS.
  # https://github.com/jwt/ruby-jwt/tree/v3.3.0#json-web-key-jwk
  def verification_keys(options = {})
    cached = Rails.cache.read("google_oidc/jwks")
    if cached && options[:kid_not_found] && cached.fetch(:fetched_at) < Time.now.to_i - 60
      cached = nil
    end
    unless cached
      response = request_json(JWKS_ENDPOINT)
      keys = response["keys"]
      raise AuthenticationFailed unless keys.is_a?(Array)
      keys = keys.select do |key|
        key.is_a?(Hash) && key["kty"] == "RSA" && key["use"] == "sig" &&
          [nil, "RS256"].include?(key["alg"])
      end
      raise AuthenticationFailed if keys.empty?
      cached = { keys: { keys: keys }, fetched_at: Time.now.to_i }
      Rails.cache.write("google_oidc/jwks", cached, expires_in: 5.minutes)
    end
    cached.fetch(:keys)
  end

  # URLs are fixed Google endpoints, never taken from client JWT headers or claims.
  # No redirects, retries, access-token persistence, or diagnostic token logging.
  def request_json(url, form: nil)
    raise AuthenticationFailed unless [TOKEN_ENDPOINT, JWKS_ENDPOINT].include?(url)
    uri = URI(url)
    request = form ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
    request["Accept"] = "application/json"
    request.set_form_data(form) if form
    body = +""
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_PEER,
      open_timeout: 5, read_timeout: 10, write_timeout: 5, max_retries: 0) do |http|
      http.request(request) do |response|
        raise AuthenticationFailed unless response.is_a?(Net::HTTPSuccess)
        response.read_body do |chunk|
          body << chunk
          raise AuthenticationFailed if body.bytesize > 1_048_576
        end
      end
    end
    parsed = JSON.parse(body)
    raise AuthenticationFailed unless parsed.is_a?(Hash)
    parsed
  rescue JSON::ParserError, SocketError, Timeout::Error, EOFError, IOError, SystemCallError,
      OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError
    raise AuthenticationFailed
  end
end
