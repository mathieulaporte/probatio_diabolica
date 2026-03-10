raise 'Missing OPENROUTER_API_KEY. Export it before running tests.' if ENV['OPENROUTER_API_KEY'].to_s.strip.empty?

RubyLLM.configure do |config|
  # Used for models like "mistralai/mistral-small-3.1-24b-instruct:free"
  config.openrouter_api_key = ENV['OPENROUTER_API_KEY']
end
