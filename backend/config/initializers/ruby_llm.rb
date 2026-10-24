require "ruby_llm/schema"

RubyLLM.configure do |config|
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
  config.default_model = "claude-sonnet-4-6"
  config.instrumenter = ActiveSupport::Notifications
end

# One log line per LLM call, plus per-job totals — see LlmUsage.
ActiveSupport::Notifications.subscribe("chat.ruby_llm") { |event| LlmUsage.record(event) }
