require_relative "boot"
require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "rails/test_unit/railtie" if ENV["RAILS_ENV"] == "test"
Bundler.require(*Rails.groups)

module AdvocaciaOnline
  class Application < Rails::Application
    config.load_defaults 8.1
    config.api_only = true
    config.time_zone = "UTC"
    config.active_record.default_timezone = :utc
    # SQL functions, grants and RLS must survive schema dumps.
    config.active_record.schema_format = :sql
    config.active_record.dump_schema_after_migration = false
    config.middleware.use ActionDispatch::Cookies
    config.action_controller.wrap_parameters_by_default = false
    config.filter_parameters += %i[code state nonce code_verifier id_token access_token refresh_token
      token csrf_token csrf secret cookie authorization email full_name office_name number]
    config.filter_redirect = ["accounts.google.com"]
    config.action_dispatch.default_headers.merge!(
      "Content-Security-Policy" => "default-src 'none'; frame-ancestors 'none'",
      "Referrer-Policy" => "no-referrer",
      "X-Content-Type-Options" => "nosniff",
      "X-Frame-Options" => "DENY",
      "Strict-Transport-Security" => "max-age=31536000"
    )
    # Request/SQL debug logs can expose OIDC payloads and bearer digests.
    config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
    config.active_record.logger = nil
    config.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new($stdout))
    config.cache_store = :memory_store, { size: 16 * 1024 * 1024 }
    config.secret_key_base = ENV.fetch("SECRET_KEY_BASE")
  end
end
