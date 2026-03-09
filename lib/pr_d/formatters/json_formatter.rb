require 'json'

module PrD
  module Formatters
    class JsonFormatter < Formatter
      def initialize(io: $stdout, serializers: {})
        super(io: io, serializers: serializers)
        @json = {}
      end

      def title(message)
        @json[:title] = { message: message }
      end

      def context(message)
        @json[:context] = { message: message, level: @level }
      end

      def success_result(message)
        @json[:success_result] = message
      end

      def failure_result(message)
        @json[:failure_result] = message
      end

      def it(description = nil, &block)
        @json[:it] = { description: description }
      end

      def end_it(description = nil, &block)
      end

      def justification(justification)
        @json[:justification] = justification
      end

      def pending(description = nil)
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

      def result(passed_count, failed_count)
        @json[:result] = { passed: passed_count, failed: failed_count }
      end

      def flush
        @io.puts JSON.pretty_generate(@json)
        super
      end
    end
  end
end
