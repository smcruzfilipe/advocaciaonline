Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_dispatch.show_exceptions = :all
  # TLS terminates at the trusted same-origin proxy; no redirect based on untrusted forwarding headers.
  config.assume_ssl = true
  config.hosts = [URI(ENV.fetch("APP_ORIGIN")).host]
end
