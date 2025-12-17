return unless Rails.application.config.respond_to?(:assets)

Rails.application.config.assets.version = "1.0"
