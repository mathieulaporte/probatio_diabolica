require 'json'

module PrD
  module Formatters
    class JsonFormatter < Formatter
      def initialize(io: $stdout, serializers: {})
        super(io: io, serializers: serializers)
        @events = []
        @summary = { passed: 0, failed: 0 }
      end

      def title(message)
        add_event(type: 'title', message: message)
      end

      def context(message)
        add_event(type: 'context', message: message)
      end

      def success_result(message)
        add_event(type: 'success_result', message: message)
      end

      def failure_result(message)
        add_event(type: 'failure_result', message: message)
      end

      def it(description = nil, &block)
        add_event(type: 'it', description: description)
      end

      def end_it(description = nil, &block)
        add_event(type: 'end_it', description: description)
      end

      def justification(justification)
        add_event(type: 'justification', message: justification)
      end

      def pending(description = nil)
        add_event(type: 'pending', description: description)
      end

      def expect(expectation)
        add_event(type: 'expect', value: serialize(expectation))
      end

      def to
        add_event(type: 'to')
      end

      def not_to
        add_event(type: 'not_to')
      end

      def matcher(matcher, sources: nil)
        add_event(type: 'matcher', matcher: matcher.class.to_s, expected: serialize(matcher.expected))
      end

      def output(message, color = nil, figure: nil, indent: 0)
        add_event(type: 'output', message: serialize(message), color: color, figure: figure, indent: indent)
      end

      def subject(subject)
        add_event(type: 'subject', value: serialize(subject))
      end

      def result(passed_count, failed_count)
        @summary = { passed: passed_count, failed: failed_count }
        add_event(type: 'result', passed: passed_count, failed: failed_count)
      end

      def flush
        payload = { format: 'prd-json-v1', events: @events, summary: @summary }
        @io.puts JSON.pretty_generate(payload)
        super
      end

      private

      def add_event(type:, **payload)
        @events << payload.merge(type:, level: @level)
      end
    end
  end
end
