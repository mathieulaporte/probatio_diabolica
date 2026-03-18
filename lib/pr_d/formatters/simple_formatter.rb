module PrD
  module Formatters
    class SimpleFormatter < Formatter
      COLOR_MAPPING = { green: "\e[32m", red: "\e[31m", yellow: "\e[33m", blue: "\e[34m", default: "\e[0m", white: "\e[37m" }.freeze

      INDENT = '│  '.freeze

      def initialize(io: $stdout, serializers: {}, mode: :verbose, display_adapters: {})
        super(io: io, serializers: serializers, mode: mode, display_adapters: display_adapters)
        @pending_expectation = nil
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
        @pending_expectation = nil
        return if synthetic?
        title(description.to_s.capitalize)
      end

      def justification(justification)
        return if synthetic?
        output("Justification: #{justification}", :white, indent: 1)
      end

      def let(name_or_value, value = MISSING_VALUE)
        return if synthetic?
        name, rendered_value = named_value_arguments(name_or_value, value)
        label = name.nil? ? 'Let' : "Let(:#{name})"
        title(label)
        render_display_node(display_node(rendered_value), color: :white, indent: 1)
      end

      def subject(subject)
        return if synthetic?
        title('Subject')
        render_display_node(display_node(subject), color: :white, indent: 1)
      end

      def subject_display_strategy
        :on_evaluation
      end

      def eager_subject_display_strategy
        :on_definition
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
        @pending_expectation = { actual: expectation, operator: :to }
      end

      def to
        return if synthetic?
        @pending_expectation ||= {}
        @pending_expectation[:operator] = :to
      end

      def not_to
        return if synthetic?
        @pending_expectation ||= {}
        @pending_expectation[:operator] = :not_to
      end

      def end_it(description = nil, &block)
      end

      def matcher(matcher, sources: nil)
        return if synthetic?
        matcher_label, expected_value = matcher_sentence_parts(matcher, sources:)
        render_expectation_sentence(matcher_label, expected_value)
      ensure
        @pending_expectation = nil
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

      def render_display_node(node, color:, indent:)
        case node[:type]
        when :code
          output("Code (#{node[:language]}):", color, indent: indent)
          output(node[:source], color, indent: indent + 1)
        when :map
          entries = node[:entries] || []
          if entries.empty?
            output('{}', color, indent: indent)
            return
          end

          entries.each do |entry|
            output("#{entry[:label]}:", color, indent: indent)
            render_display_node(entry[:value], color: color, indent: indent + 1)
          end
        when :list
          items = node[:items] || []
          if items.empty?
            output('[]', color, indent: indent)
            return
          end

          items.each_with_index do |entry, index|
            output("[#{index}]:", color, indent: indent)
            render_display_node(entry, color: color, indent: indent + 1)
          end
        when :image
          output("Image file: #{node[:path]}", color, indent: indent)
        when :pdf_file
          output("PDF file: #{node[:path]}", color, indent: indent)
        when :pdf_reader
          output('PDF::Reader value', color, indent: indent)
        else
          output(node[:text], color, indent: indent)
        end
      end

      def indented_message(message, indent_incr: 0)
        "#{INDENT * (@level + indent_incr)}#{message}"
      end

      def render_expectation_sentence(matcher_label, expected_value)
        actual_provided = @pending_expectation && @pending_expectation.key?(:actual)
        actual = actual_provided ? @pending_expectation[:actual] : nil
        operator = expectation_operator_text(@pending_expectation && @pending_expectation[:operator])
        actual_text = actual_provided ? expectation_inline_value(actual) : '(subject)'
        expected_present = !expected_value.equal?(NO_EXPECTED_VALUE)
        expected_text = expected_present ? expectation_inline_value(expected_value) : nil

        sentence = +"Expect #{actual_text} #{operator} #{matcher_label}"
        sentence << " #{expected_text}" unless expected_text.nil?
        output(sentence, :white, indent: 1)

        render_expectation_code_block('Actual', actual, indent: 2)
        render_expectation_code_block('Expected', expected_value, indent: 2) if expected_present
      end

      def expectation_inline_value(value)
        return "(#{value.language} code)" if code_object?(value)

        serialize(value).to_s
      end

      def render_expectation_code_block(prefix, value, indent:)
        return unless code_object?(value)

        output("#{prefix} code (#{value.language}):", :white, indent: indent)
        output(value.source, :white, indent: indent + 1)
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
