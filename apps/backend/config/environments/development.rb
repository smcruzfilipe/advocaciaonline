Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = false
  config.debug_exception_response_format = :api
  config.hosts = [URI(ENV.fetch("APP_ORIGIN")).host]
end
