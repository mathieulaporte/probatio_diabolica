module PrD
  module Formatters
    class SimpleFormatter < Formatter
      COLOR_MAPPING = { green: "\e[32m", red: "\e[31m", yellow: "\e[33m", blue: "\e[34m", default: "\e[0m", white: "\e[37m" }.freeze

      INDENT = '│  '.freeze

      def initialize(io: $stdout, serializers: {}, mode: :verbose)
        super(io: io, serializers: serializers, mode: mode)
      end

      def context(message)
        return if synthetic?
        output(message, :yellow)
      end

      def success_result(message)
        if synthetic?
          output("PASS: #{@current_test_title}", :green)
          return
        end
        output("✓ #{message}", :green)
      end

      def failure_result(message)
        if synthetic?
          output("FAIL: #{@current_test_title}", :red)
          return
        end
        output("✗ #{message}", :red)
      end

      def it(description = nil, &block)
        @current_test_title = description.to_s
        return if synthetic?
        title(description.to_s.capitalize)
      end

      def justification(justification)
        return if synthetic?
        output("Justification: #{justification}", :white, indent: 1)
      end

      def let(value)
      end

      def subject(subject)
        return if synthetic?
        title('Subject')
        if code_object?(subject)
          output("Code (#{subject.language}):", :white, indent: 1)
          output(subject.source, :white, indent: 2)
        else
          output(subject, :white, indent: 1)
        end
      end

      def pending(description = nil)
        if synthetic?
          output("PENDING: #{description || 'Pending test'}", :yellow)
          return
        end
        title(description || 'Pending test')
        output('⚠ This test is pending and has not been executed.', :yellow)
      end

      def expect(expectation)
        return if synthetic?
        if code_object?(expectation)
          output("Expect (#{expectation.language}):", :white, indent: 1)
          output(expectation.source, :white, indent: 2)
        else
          output("Expect: #{expectation}", :white, indent: 1)
        end
      end

      def to
        return if synthetic?
        output('To:', :white, indent: 1)
      end

      def not_to
        return if synthetic?
        output('Not to:', :white, indent: 1)
      end

      def end_it(description = nil, &block)
      end

      def matcher(matcher, sources: nil)
        return if synthetic?
        case matcher
        when Matchers::EqMatcher
          output_matcher_value('Be equal to', matcher.expected)
        when Matchers::BeMatcher
          output_matcher_value('Be the same object as', matcher.expected)
        when Matchers::IncludesMatcher
          output_matcher_value('Include', matcher.expected)
        when Matchers::HaveMatcher
          output_matcher_value('Have', matcher.expected)
        when Matchers::LlmMatcher
          output_matcher_value('Satisfy condition', matcher.expected)
        when Matchers::AllMatcher
          if sources
            code_line = matcher.expected.source_location.last.to_i
            code = sources.lines[code_line - 1]
            output("all match condition: #{code.strip}", :white, indent: 2)
          else
            output('all match the given condition', :white, indent: 2)
          end
        else
          output("match: #{matcher.class}", :white, indent: 2)
        end
      end

      def result(passed_count, failed_count)
        color = failed_count > 0 ? :red : :green
        output("#{passed_count} passed, #{failed_count} failed", color)
      end

      private

      def output(message, color = :default, figure: nil, indent: 0)
        colored_message = "#{COLOR_MAPPING[color]}#{message}#{COLOR_MAPPING[:default]}"
        case message
        when Symbol
          @io.puts "#{INDENT * indent}#{message}"
        when Array
          message.each { |line| output(line, color, figure: figure, indent: indent) }
        when PrD::Code
          output("Code (#{message.language}):", color, indent: indent)
          output(message.source, color, indent: indent + 1)
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

      def output_matcher_value(label, value)
        if code_object?(value)
          output("#{label} (#{value.language}):", :white, indent: 2)
          output(value.source, :white, indent: 3)
        else
          output("#{label}: #{value}", :white, indent: 2)
        end
      end

      def indented_message(message, indent_incr: 0)
        "#{INDENT * (@level + indent_incr)}#{message}"
      end
    end
  end
end
