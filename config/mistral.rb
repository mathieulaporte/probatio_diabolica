raise 'Missing MISTRAL_API_KEY. Export it before running tests.' if ENV['MISTRAL_API_KEY'].to_s.strip.empty?

RubyLLM.configure do |config|
  # Direct Mistral provider (not OpenRouter)
  config.mistral_api_key = ENV['MISTRAL_API_KEY']
  config.default_model = 'mistral-small-latest'
end
