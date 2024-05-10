# frozen_string_literal: true
# typed: strict

if ENV['SENTRY_DSN_API']
  Sentry.init do |config|
    config.dsn = ENV['SENTRY_DSN_API']
    # enable performance monitoring
    config.enable_tracing = true
    # get breadcrumbs from logs
    config.breadcrumbs_logger = [:http_logger]
  end
end
