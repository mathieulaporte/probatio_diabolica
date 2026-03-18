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
        render_structured_subject_value(subject, color: :white, indent: 1)
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
          output("Expect: #{serialize(expectation)}", :white, indent: 1)
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
        if ferrum_node?(message)
          output(serialize(message).to_s, color, figure: figure, indent: indent)
          return
        end

        case message
        when Symbol
          @io.puts "#{INDENT * indent}#{message}"
        when Array
          message.each { |line| output(line, color, figure: figure, indent: indent) }
        when PrD::Code
          output("Code (#{message.language}):", color, indent: indent)
          output(message.source, color, indent: indent + 1)
        when String
          normalized_message = normalize_text(message)
          colored_message = "#{COLOR_MAPPING[color]}#{normalized_message}#{COLOR_MAPPING[:default]}"

          if normalized_message.include?("\n")
            @io.puts "#{COLOR_MAPPING[color]}#{INDENT * indent}--- Code Block ---#{COLOR_MAPPING[:default]}"
            normalized_message.split("\n").each { |line| @io.puts "#{INDENT * (indent + 1)}#{line}" }
            @io.puts "#{COLOR_MAPPING[color]}#{INDENT * indent}--- End Block ---#{COLOR_MAPPING[:default]}"
          else
            @io.puts indented_message(colored_message)
          end
        when File
          if message.path.end_with?('.png', '.jpg', '.jpeg')
            output("Image file: #{message.path}", color, indent: indent)
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
          output("#{label}: #{serialize(value)}", :white, indent: 2)
        end
      end

      def render_structured_subject_value(value, color:, indent:)
        if code_object?(value)
          output("Code (#{value.language}):", color, indent: indent)
          output(value.source, color, indent: indent + 1)
          return
        end

        if value.is_a?(Hash)
          if value.empty?
            output('{}', color, indent: indent)
            return
          end

          value.each do |key, nested_value|
            output("#{serialize(key)}:", color, indent: indent)
            render_structured_subject_value(nested_value, color: color, indent: indent + 1)
          end
          return
        end

        if value.is_a?(Array)
          if value.empty?
            output('[]', color, indent: indent)
            return
          end

          value.each_with_index do |entry, index|
            output("[#{index}]:", color, indent: indent)
            render_structured_subject_value(entry, color: color, indent: indent + 1)
          end
          return
        end

        image_path = image_file_path(value)
        unless image_path.nil?
          output("Image file: #{image_path}", color, indent: indent)
          return
        end

        output(value, color, indent: indent)
      end

      def image_file_path(value)
        path = file_path(value)
        return nil if path.nil?
        return nil unless path.match?(/\.(png|jpe?g)\z/i)

        path
      end

      def file_path(value)
        return value.path if value.is_a?(File)
        return nil unless value.respond_to?(:path)

        path = value.path
        path.is_a?(String) && !path.empty? ? path : nil
      rescue StandardError
        nil
      end

      def indented_message(message, indent_incr: 0)
        "#{INDENT * (@level + indent_incr)}#{message}"
      end

      def normalize_text(value)
        string = value.to_s
        return string if string.encoding == Encoding::UTF_8 && string.valid_encoding?

        if string.encoding == Encoding::ASCII_8BIT
          return string.dup.force_encoding(Encoding::UTF_8).scrub('?')
        end

        string.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '?')
      rescue Encoding::ConverterNotFoundError, Encoding::CompatibilityError, Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
        string.dup.force_encoding(Encoding::UTF_8).scrub('?')
      end
    end
  end
end
