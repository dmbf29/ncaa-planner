require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Backend
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # Enable minimal cookie/session middleware for Devise + JWT (required to avoid DisabledSessionError)
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore, key: "_ncaa_planner_session", same_site: :lax
  end
end


{
  "Quarterback" => {
    "Backfield Creator" => "BC",
    "Dual Threat" => "DT",
    "Pocket Passer" => "PP",
    "Pure Runner" => "PR"
  },
  "Halfback" => {
    "Backfield Threat" => "BT",
    "Contact Seeker" => "CS",
    "East/West Playmaker" => "EWP",
    "Elusive Bruiser" => "EB",
    "North/South Blocker" => "NSB",
    "North/South Receiver" => "NSR"
  },
  "Fullback" => {
    "Blocking" => "B",
    "Utility" => "U"
  },
  "Wide Receiver / Tight End" => {
    "Contested Specialist" => "CS",
    "Elusive Route Runner" => "ERR",
    "Gadget" => "G",
    "Gritty Possession" => "GP",
    "Possession" => "P",
    "Physical Route Runner" => "PRR",
    "Pure Blocker" => "PB",
    "Route Artist" => "RA",
    "Speedster" => "S",
    "Vertical Threat" => "VT",
  },
  "Offensive Line" => {
    "Agile" => "A",
    "Pass Protector" => "PP",
    "Raw Strength" => "RS",
    "Well Rounded" => "WR"
  },
  "Defensive Line" => {
    "Edge Setter" => "ES",
    "Gap Specialist" => "GS",
    "Power Rusher" => "PR",
    "Pure Power" => "PP",
    "Speed Rusher" => "SR"
  },
  "Linebacker" => {
    "Signal Caller" => "SC",
    "Lurker" => "L",
    "Thumper" => "T"
  },
    "Boundary Corner" => "BC",
    "Bump and Run" => "BR",
    "Field" => "F",
    "Zone" => "Z",
    "Coverage Specialist" => "CS",
    "Box Specialist" => "BS",
    "Hybrid" => "H",
}
