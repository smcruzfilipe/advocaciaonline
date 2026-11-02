max_threads = Integer(ENV.fetch("RAILS_MAX_THREADS", "5"))
threads max_threads, max_threads
port Integer(ENV.fetch("PORT", "3000"))
environment ENV.fetch("RAILS_ENV", "production")
pidfile "/tmp/advocacia-puma.pid"
