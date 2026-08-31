# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin Ajax requests.

# Read more: https://github.com/cyu/rack-cors

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("FRONTEND_URL", "http://localhost:5173")

    resource "*",
             headers: :any,
             expose: [ "Authorization" ],
             methods: %i[get post put patch delete options head]
  end

  # Public broadcast endpoints (win totals / weekly recaps) are meant for
  # third-party tools, so allow them to be fetched from any origin.
  allow do
    origins "*"

    resource "/api/v1/dynasties/*/seasons/*/win_totals",
             headers: :any,
             methods: %i[get options]

    resource "/api/v1/dynasties/*/seasons/*/weeks",
             headers: :any,
             methods: %i[get options]

    resource "/api/v1/dynasties/*/seasons/*/team_breakdown",
             headers: :any,
             methods: %i[get options]

    resource "/api/v1/dynasties/*/seasons/*/midseason_report_cards",
             headers: :any,
             methods: %i[get options]
  end
end
