class AppSettings
  def self.origin
    value = ENV.fetch("APP_ORIGIN")
    uri = URI(value)
    unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil? &&
        uri.query.nil? && uri.fragment.nil? && ["", "/"].include?(uri.path)
      raise ArgumentError, "APP_ORIGIN must be an HTTPS origin without credentials, path, query or fragment"
    end
    value.delete_suffix("/")
  end

  def self.google_client_id
    ENV.fetch("GOOGLE_CLIENT_ID").presence || raise(ArgumentError, "GOOGLE_CLIENT_ID is required")
  end

  def self.google_client_secret
    ENV.fetch("GOOGLE_CLIENT_SECRET").presence || raise(ArgumentError, "GOOGLE_CLIENT_SECRET is required")
  end
end
