module LlmSpec
  module Formatters
    class HtmlFormatter < Formatter

      def initialize(io: $stdout, serializers: {})
        super(io: io, serializers: serializers)
        @io << '<html><head><link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@2/css/pico.min.css"></head><body><main class="container">'
      end

      def context(message)
        @io << "<h#{@level + 1}>#{message}</h#{@level + 1}>"
      end

      def success_result(message)
        @io << "<div class='success'>✓ #{message}</div>"
      end

      def failure_result(message)
        @io << "<div class='failure'>✗ #{message}</div>"
      end

      def it(description = nil, &block)
        @io << "<h#{@level + 1}>#{description}</h#{@level + 1}>"
        @io << '<div class="grid">'
      end

      def end_it(description = nil, &block)
        @io << '</div>'
      end

      def justification(justification)
        @io << "<p><strong>Justification:</strong> #{justification}</p>"
      end

      def let(value)
      end

      def subject(subject)
        # title('Subject')
        # output(subject, :white, indent: 1)
      end

      def pending(description = nil)
        @io << "<h#{@level + 1}>#{description || 'Pending test'}</h#{@level + 1}>"
        @io << "<p>⚠ This test is pending and has not been executed.</p>"
      end

      def expect(expectation)
        @io << "<p>Expect: #{expectation}</p>"
      end

      def to
        @io << "<p>To:</p>"
      end

      def not_to
        @io << "<p>Not to:</p>"
      end

      def matcher(matcher, sources: nil)
        # case matcher
        # when Matchers::EqMatcher
        #   output("Be equal to: #{matcher.expected}", :white, indent: 2)
        # when Matchers::BeMatcher
        #   output("Be the same object as: #{matcher.expected}", :white, indent: 2)
        # when Matchers::IncludesMatcher
        #   output("Include: #{matcher.expected}", :white, indent: 2)
        # when Matchers::HaveMatcher
        #   output("Have: #{matcher.expected}", :white, indent: 2)
        # when Matchers::LlmMatcher
        #   output("Satisfy condition: #{matcher.expected}", :white, indent: 2)
        # when Matchers::AllMatcher
        #   if sources
        #     code_line = matcher.expected.source_location.last.to_i
        #     code = sources.lines[code_line - 1]
        #     output("all match condition: #{code.strip}", :white, indent: 2)
        #   else
        #     output('all match the given condition', :white, indent: 2)
        #   end
        # else
        #   output("match: #{matcher.class}", :white, indent: 2)
        # end

        case matcher
        when Matchers::EqMatcher
          @io << "<p>Be equal to: #{matcher.expected}</p>"
        when Matchers::BeMatcher
          @io << "<p>Be the same object as: #{matcher.expected}</p>"
        when Matchers::IncludesMatcher
          @io << "<p>Include: #{matcher.expected}</p>"
        when Matchers::HaveMatcher
          @io << "<p>Have: #{matcher.expected}</p>"
        when Matchers::LlmMatcher
          @io << "<p>Satisfy condition: #{matcher.expected}</p>"
        when Matchers::AllMatcher
          if sources
            code_line = matcher.expected.source_location.last.to_i
            code = sources.lines[code_line - 1]
            @io << "<p>All match condition: #{code.strip}</p>"
          else
            @io << "<p>All match the given condition</p>"
          end
        else
          @io << "<p>Match: #{matcher.class}</p>"
        end
      end

      def result(passed_count, failed_count)
        # color = failed_count > 0 ? :red : :green
        # output("#{passed_count} passed, #{failed_count} failed", color)
      end

      def flush
        @io << '</main></body></html>'
        @io.flush
      end

      private

      def output(message, color = :default, figure: nil, indent: 0)
        colored_message = "#{COLOR_MAPPING[color]}#{message}#{COLOR_MAPPING[:default]}"
        case message
        when Symbol
          @io.puts "#{INDENT * indent}#{message}"
        when Array
          message.each { |line| output(line, color, figure: figure, indent: indent) }
        when String
          if message.include?("\n")
            @io.puts "#{COLOR_MAPPING[color]}#{INDENT * indent}--- Code Block ---#{COLOR_MAPPING[:default]}"
            message.split("\n").each { |line| @io.puts "#{INDENT * (indent + 1)}#{line}" }
            @io.puts "#{COLOR_MAPPING[color]}#{INDENT * indent}--- End Block ---#{COLOR_MAPPING[:default]}"
          else
            @io.puts indented_message(colored_message)
          end
        when File
          if message.path.end_with?('.png', '.jpg', '.jpeg')
            # output(AsciiArt.new(message.path).to_ascii_art(color: true, width: 120), color, indent: indent)
            output("Caption: #{figure}", color, indent: indent + 1) if figure
          elsif message.path.end_with?('.csv')
            output("CSV file: #{message.path}", color, indent: indent)
          elsif message.path.end_with?('.txt')
            output("Text file: #{message.path}", color, indent: indent)
            if File.exist?(message.path)
              File.readlines(message.path).each { |line| output(line.chomp, color, indent: indent + 1) }
            end
          else
            output("File: #{message.path}", color, indent: indent)
          end
        else
          if @serializers[message.class]
            output(@serializers[message.class].call(message), color, figure: figure, indent: indent)
          else
            output(message.to_s, color, figure: figure, indent: indent)
          end
        end
      end

      def title(message)
        output(message, :yellow)
      end

      def indented_message(message, indent_incr: 0)
        "#{INDENT * (@level + indent_incr)}#{message}"
      end
    end
  end
end
