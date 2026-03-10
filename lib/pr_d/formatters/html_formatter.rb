require 'cgi'

module PrD
  module Formatters
    class HtmlFormatter < Formatter
      def initialize(io: $stdout, serializers: {})
        super(io: io, serializers: serializers)
        @io << '<html><head><link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@2/css/pico.min.css"></head><body><main class="container">'
      end

      def context(message)
        level = heading_level
        @io << "<h#{level}>#{escape(message)}</h#{level}>"
      end

      def success_result(message)
        @io << "<div class='success'>✓ #{escape(message)}</div>"
      end

      def failure_result(message)
        @io << "<div class='failure'>✗ #{escape(message)}</div>"
      end

      def it(description = nil, &block)
        level = heading_level
        @io << "<h#{level}>#{escape(description)}</h#{level}>"
        @io << '<div class="grid">'
      end

      def end_it(description = nil, &block)
        @io << '</div>'
      end

      def justification(justification)
        @io << "<p><strong>Justification:</strong> #{escape(justification)}</p>"
      end

      def let(value)
      end

      def subject(subject)
        @io << "<h#{heading_level}>Subject</h#{heading_level}>"
        @io << "<p>#{escape(serialize(subject).to_s)}</p>"
      end

      def pending(description = nil)
        level = heading_level
        @io << "<h#{level}>#{escape(description || 'Pending test')}</h#{level}>"
        @io << "<p>⚠ This test is pending and has not been executed.</p>"
      end

      def expect(expectation)
        @io << "<p>Expect: #{escape(serialize(expectation).to_s)}</p>"
      end

      def to
        @io << "<p>To:</p>"
      end

      def not_to
        @io << "<p>Not to:</p>"
      end

      def matcher(matcher, sources: nil)
        case matcher
        when Matchers::EqMatcher
          @io << "<p>Be equal to: #{escape(serialize(matcher.expected).to_s)}</p>"
        when Matchers::BeMatcher
          @io << "<p>Be the same object as: #{escape(serialize(matcher.expected).to_s)}</p>"
        when Matchers::IncludesMatcher
          @io << "<p>Include: #{escape(serialize(matcher.expected).to_s)}</p>"
        when Matchers::HaveMatcher
          @io << "<p>Have: #{escape(serialize(matcher.expected).to_s)}</p>"
        when Matchers::LlmMatcher
          @io << "<p>Satisfy condition: #{escape(serialize(matcher.expected).to_s)}</p>"
        when Matchers::AllMatcher
          if sources
            code_line = matcher.expected.source_location.last.to_i
            code = sources.lines[code_line - 1]
            @io << "<p>All match condition: #{escape(code.strip)}</p>"
          else
            @io << "<p>All match the given condition</p>"
          end
        else
          @io << "<p>Match: #{escape(matcher.class.to_s)}</p>"
        end
      end

      def result(passed_count, failed_count)
        summary_class = failed_count > 0 ? 'failure' : 'success'
        @io << "<p class='#{summary_class}'><strong>#{passed_count} passed, #{failed_count} failed</strong></p>"
      end

      def flush
        @io << '</main></body></html>'
        super
      end

      private

      def heading_level
        [[@level + 1, 1].max, 6].min
      end

      def escape(message)
        CGI.escape_html(message.to_s)
      end
    end
  end
end
