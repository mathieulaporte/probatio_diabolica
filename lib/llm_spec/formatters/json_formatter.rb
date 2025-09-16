module LlmSpec
  module Formatters
    class JsonFormatter < Formatter
      def initialize(io: $stdout, serializers: {})
        @io = io
        @serializers = serializers
        @json = {}
      end

      def context(message, level:)
        @json[:title] = { message: message, level: level }
      end

      def success_result(message)
        @json[:success_result] = message
      end

      def failure_result(message)
        @json[:failure_result] = message
      end

      def it(description = nil, level: 1, &block)
        @json[:it] = { description: description }
      end

      def pending(description = nil, level: 1)
        @json[:pending] = { description: description }
      end

      def expect(expectation)
        @json[:expect] = expectation
      end

      def to
        @json[:to] = {}
      end

      def not_to
        @json[:not_to] = {}
      end

      def matcher(matcher, sources: nil)
        @json[:matcher] = { matcher: matcher }
      end

      def output(message, color = nil, figure: nil, indent: 0)
        @json[:output] = { message: message }
      end

      def subject(subject)
        @json[:subject] = subject
      end

      def flush
        @io.puts JSON.pretty_generate(@json)
        @io.flush
      end
    end
  end
end
