# Token and dollar accounting for every LLM call (RubyLLM emits a "chat.ruby_llm"
# event per call). Each call is logged as one line:
#
#   [LLM] claude-sonnet-4-6 in=3210 out=412 cache_read=0 $0.0158 2.1s
#
# Wrap a unit of work in LlmUsage.track to also get a total for it (and the totals back):
#
#   usage = LlmUsage.track("game 1429") { ...many calls... }
#   # => [LLM] game 1429: 22 calls, in=70211 out=9120 cache_read=0 $0.35
#
# Totals are per thread, which matches how jobs run (one thread, calls in sequence).
module LlmUsage
  Totals = Struct.new(:calls, :input_tokens, :output_tokens, :cache_read_tokens, :cost, keyword_init: true) do
    def to_h
      super.merge(cost: cost.round(4))
    end
  end

  def self.record(event)
    payload = event.payload
    response = payload[:response]
    return unless response.respond_to?(:tokens) && response.tokens

    model = payload[:model_info]
    cost = model ? model.cost_for(response.tokens).total.to_f : 0.0
    input, output = payload[:input_tokens].to_i, payload[:output_tokens].to_i
    cache_read = payload[:cached_tokens].to_i

    Rails.logger.info(format("[LLM] %s in=%d out=%d cache_read=%d $%.4f %.1fs", payload[:model], input, output, cache_read, cost, event.duration / 1000.0))

    totals = Thread.current[:llm_usage]
    return unless totals

    totals.calls += 1
    totals.input_tokens += input
    totals.output_tokens += output
    totals.cache_read_tokens += cache_read
    totals.cost += cost
  end

  # Runs the block, logs a summary line, and returns the Totals (the block's value is
  # discarded; use #track_with_result to keep it).
  def self.track(label, &block)
    track_with_result(label, &block).last
  end

  def self.track_with_result(label)
    previous = Thread.current[:llm_usage]
    totals = Thread.current[:llm_usage] = Totals.new(calls: 0, input_tokens: 0, output_tokens: 0, cache_read_tokens: 0, cost: 0.0)
    result = begin
      yield
    ensure
      Rails.logger.info(format("[LLM] %s: %d calls, in=%d out=%d cache_read=%d $%.2f", label, totals.calls, totals.input_tokens,
                               totals.output_tokens, totals.cache_read_tokens, totals.cost))
    end
    [ result, totals ]
  ensure
    Thread.current[:llm_usage] = previous
  end
end
