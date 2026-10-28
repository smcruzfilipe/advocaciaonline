Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = false
  config.consider_all_requests_local = false
  config.action_dispatch.show_exceptions = :rescuable
  # Tests run as runtime after a separate migrator has prepared the test database.
  config.active_record.maintain_test_schema = false
  config.hosts = [URI(ENV.fetch("APP_ORIGIN")).host]
end
