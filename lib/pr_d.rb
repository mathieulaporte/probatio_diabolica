require 'zeitwerk'
require 'ruby_llm'

module PrD
  LOADER = Zeitwerk::Loader.new
  LOADER.push_dir(File.join(__dir__, 'pr_d'), namespace: self)
  LOADER.setup

  class Runtime
    include PrD::Helpers::ChromeHelper
    include PrD::Helpers::SourceCodeHelper

    class TestResult
      attr_reader :comment, :pass

      def initialize(comment:, pass:)
        @comment = comment
        @pass = pass
      end
    end

    def self.run(tests)
      new.run(tests)
    end

    DEFAULT_MATCHERS = [
      PrD::Matchers::AllMatcher,
      PrD::Matchers::BeMatcher,
      PrD::Matchers::EmptyMatcher,
      PrD::Matchers::EqMatcher,
      PrD::Matchers::GtMatcher,
      PrD::Matchers::GteMatcher,
      PrD::Matchers::HaveMatcher,
      PrD::Matchers::IncludesMatcher,
      PrD::Matchers::LtMatcher,
      PrD::Matchers::LlmMatcher,
      PrD::Matchers::LteMatcher
    ].freeze
    LET_ACCESS_HISTORY_LIMIT = 64

    def initialize(output_dir:, formatter: nil, matchers: [], verbose: true, config_file: nil)
      @actual = nil
      @actual_label = nil
      @passed_count = 0
      @failed_count = 0
      @formatter = formatter || PrD::Formatters::SimpleFormatter.new
      @output_dir = output_dir
      @verbose = verbose
      @recent_let_accesses = []
      (DEFAULT_MATCHERS + matchers).each do |matcher|
        define_singleton_method(matcher::DSL_HELPER_NAME) do |*args|
          callsite = caller_locations(1, 1).first

          if matcher == PrD::Matchers::LlmMatcher
            model = current_model
            raise ArgumentError, 'LLM matcher requires a model. Set model: on context/it before using satisfy().' if model.nil?

            begin
              matcher_instance = matcher.new(*args, client: RubyLLM.chat(model: model))
            rescue StandardError => e
              raise ArgumentError, "Unable to initialize LLM client for model '#{model}': #{e.message}"
            end
          elsif matcher == PrD::Matchers::BeMatcher && args.length == 1 && args.first.is_a?(PrD::Matchers::Matcher)
            matcher_instance = args.first
          else
            matcher_instance = matcher.new(*args)
          end

          if args.length == 1 && matcher_instance.respond_to?(:expected_label=)
            expected_label = consume_let_label_for_value(args.first, callsite:)
            matcher_instance.expected_label = expected_label unless expected_label.nil?
          end

          matcher_instance
        end
      end
      @models_stack = []
      @hook_scopes = [{ before: [], after: [] }]
      @subject_definition_stack = [nil]
      @context_depth = 0
      @eager_subject_rendered = false
      reset_subject_memoization!
      if config_file
        if File.exist?(config_file)
          require File.expand_path(config_file)
        elsif File.exist?(File.expand_path(config_file, Dir.pwd))
          require File.expand_path(config_file, Dir.pwd)
        else
          require config_file
        end
      elsif File.exist?('prd_helper.rb')
        require './prd_helper'
      end
    end

    attr_reader :passed_count, :failed_count

    def describe(description, model: nil, &block)
      context(description, model: model, &block)
    end

    def context(description, model: nil, &block)
      @context_depth += 1
      @formatter.context(description)
      @formatter.increment_level
      @models_stack.push(model) if model
      @hook_scopes << { before: [], after: [] }
      @subject_definition_stack << @subject_definition_stack.last

      instance_eval(&block)
    rescue StandardError => e
      if @context_depth == 1
        raise e
      else
        report_context_execution_error(e, description:)
      end
    ensure
      @subject_definition_stack.pop
      @hook_scopes.pop
      @models_stack.pop if model
      @formatter.decrement_level
      @context_depth -= 1 if @context_depth.positive?
    end

    def it(description = nil, model = nil, &block)
      result = nil
      execution_error = nil
      before_hooks = collect_before_hooks
      after_hooks = collect_after_hooks
      @current_expectation_results = []

      begin
        description ||= infer_example_description(block)
        @models_stack.push(model) if model
        @formatter.it(description, &block) if @verbose
        @formatter.increment_level
        reset_subject_memoization!
        clear_recent_let_accesses!

        before_hooks.each { |hook| instance_eval(&hook) }
        result = block.call
      rescue => e
        execution_error = e
      ensure
        after_error = run_after_hooks(after_hooks)
        execution_error ||= after_error

        if execution_error
          report_test_execution_error(execution_error)
        else
          begin
            process_test_result(result)
          rescue StandardError => e
            report_test_execution_error(e)
          end
        end

        @formatter.end_it(description, &block)
        @formatter.decrement_level
        @models_stack.pop if model
        @current_expectation_results = nil
        reset_subject_memoization!
        clear_recent_let_accesses!
      end

      result
    end

    def let(name, &block)
      block_result = nil
      let_error = nil

      begin
        block_result = block.call
      rescue StandardError => e
        let_error = e
      end

      if @verbose
        rendered_value =
          if let_error
            "Error while evaluating let(:#{name}): #{let_error.class}: #{normalized_error_message(let_error)}"
          else
            block_result
          end
        formatter_let_arity = @formatter.method(:let).arity
        if formatter_let_arity == 1
          @formatter.let(rendered_value)
        else
          @formatter.let(name, rendered_value)
        end
      end

      instance_variable_set("@#{name}", block_result)
      define_singleton_method(name) do
        if let_error
          raise let_error.class, normalized_error_message(let_error), let_error.backtrace
        end

        record_let_access(name, block_result, callsite: caller_locations(1, 1).first)
        block_result
      end
    end

    def before(&block)
      raise ArgumentError, 'before requires a block.' unless block_given?

      current_hook_scope[:before] << block
    end

    def after(&block)
      raise ArgumentError, 'after requires a block.' unless block_given?

      current_hook_scope[:after] << block
    end

    def to(matcher)
      @formatter.to
      @formatter.matcher(matcher)
      result = matcher.matches?(@actual)
      final_result = if result.pass
        result
      else
        TestResult.new(
          comment: merge_expectation_comments(
            build_expectation_failure_message(matcher, negated: false),
            result.comment
          ),
          pass: false
        )
      end

      record_expectation_result(final_result)
      final_result
    end

    def not_to(matcher)
      @formatter.not_to
      @formatter.matcher(matcher)
      result = matcher.matches?(@actual)
      final_result = unless result.pass
        TestResult.new(comment: result.comment, pass: true)
      else
        TestResult.new(
          comment: merge_expectation_comments(
            build_expectation_failure_message(matcher, negated: true),
            result.comment
          ),
          pass: false
        )
      end

      record_expectation_result(final_result)
      final_result
    end

    def subject(&block)
      if block_given?
        @subject_definition_stack[-1] = block
        return nil
      end

      evaluate_subject_value(render: true)
    end

    def subject!(&block)
      raise ArgumentError, 'subject! requires a block.' unless block_given?

      subject(&block)
      @eager_subject_rendered = false
      render_in_before = @verbose && @formatter.eager_subject_display_strategy == :on_evaluation
      before do
        value = evaluate_subject_value(render: render_in_before)
        if @verbose && @formatter.eager_subject_display_strategy == :on_definition && !@eager_subject_rendered
          @formatter.subject(value)
          @eager_subject_rendered = true
        end
      end
      nil
    end

    def expect(*args, &block)
      callsite = caller_locations(1, 1).first

      if args.length >= 1
        @actual = args.first
        @actual_label = consume_let_label_for_value(@actual, callsite:)
        @formatter.expect(@actual, label: @actual_label)
      elsif block_given?
        @actual = block.call(subject)
        @actual_label = nil
        @formatter.expect(@actual, label: nil)
      else
        @actual = subject
        @actual_label = consume_let_label_for_value(@actual, callsite:)
        # Avoid to display the subject value twice
        @formatter.expect('The subject', label: @actual_label)
      end
      self
    end

    def pending(description = nil, &block)
      @formatter.pending(description || 'Pending test') if @verbose
    end

    def current_model
      @models_stack.last
    end

    def run(tests)
      raise ArgumentError, 'No tests found. Provide at least one spec content to run.' if tests.nil? || tests.empty?

      @tests = tests
      @tests.each_with_index do |test_source, index|
        @current_test_source = test_source
        instance_eval(test_source)
      rescue StandardError => e
        report_spec_source_execution_error(e, source_index: index + 1)
      ensure
        @current_test_source = nil
      end
    rescue StandardError => e
      $stderr.puts "An error occurred while running tests: #{e.message}"
      $stderr.puts e.backtrace.join("\n")
      @formatter.failure_result("An error occurred while running tests: #{e.message}")
      @failed_count += 1
    ensure
      close_chrome_browser if respond_to?(:close_chrome_browser, true)
      @formatter.result(@passed_count, @failed_count)
      @formatter.flush
    end

    def success?
      @failed_count.zero?
    end

    private

    def formatted_time
      Time.now.utc.strftime('%Y-%m-%d %H:%M:%S UTC')
    end

    def reset_subject_memoization!
      @subject_memoized = false
      @subject_value = nil
    end

    def clear_recent_let_accesses!
      @recent_let_accesses = []
    end

    def record_let_access(name, value, callsite: nil)
      @recent_let_accesses << {
        name: name.to_s,
        value: value,
        path: callsite&.path,
        lineno: callsite&.lineno
      }
      @recent_let_accesses.shift if @recent_let_accesses.length > LET_ACCESS_HISTORY_LIMIT
      nil
    end

    def consume_let_label_for_value(value, callsite:)
      return nil if @recent_let_accesses.nil? || @recent_let_accesses.empty?

      index = preferred_let_access_index(value, callsite:)
      return nil if index.nil?

      @recent_let_accesses.delete_at(index)[:name]
    end

    def preferred_let_access_index(value, callsite:)
      same_line = find_let_access_index(value) do |entry|
        same_path = !callsite.nil? && entry[:path] == callsite.path
        same_line = !callsite.nil? && entry[:lineno] == callsite.lineno
        same_path && same_line
      end
      return same_line unless same_line.nil?

      near_line = find_let_access_index(value) do |entry|
        next false if callsite.nil?
        next false unless entry[:path] == callsite.path

        (entry[:lineno] - callsite.lineno).abs <= 5
      end
      return near_line unless near_line.nil?

      nil
    end

    def find_let_access_index(value)
      (@recent_let_accesses.length - 1).downto(0) do |index|
        entry = @recent_let_accesses[index]
        next unless same_runtime_value?(entry[:value], value)
        next unless yield(entry)

        return index
      end
      nil
    end

    def same_runtime_value?(left, right)
      return true if left.equal?(right)
      return false unless left.class == right.class

      left == right
    rescue StandardError
      false
    end

    def evaluate_subject_value(render:)
      subject_block = @subject_definition_stack.last
      return nil if subject_block.nil?

      unless @subject_memoized
        @subject_value = instance_eval(&subject_block)
        @subject_memoized = true
        if render && @verbose && @formatter.subject_display_strategy == :on_evaluation
          @formatter.subject(@subject_value)
        end
      end

      @subject_value
    end

    def current_hook_scope
      @hook_scopes.last
    end

    def infer_example_description(block)
      return nil if block.nil?
      return nil if @current_test_source.nil?

      line_number = block.source_location&.last
      return nil if line_number.nil?

      @current_test_source.lines[line_number - 1]&.strip
    rescue StandardError
      nil
    end

    def collect_before_hooks
      @hook_scopes.flat_map { |scope| scope[:before] }
    end

    def collect_after_hooks
      @hook_scopes.reverse.flat_map { |scope| scope[:after].reverse }
    end

    def run_after_hooks(hooks)
      first_error = nil
      hooks.each do |hook|
        begin
          instance_eval(&hook)
        rescue StandardError => e
          first_error ||= e
        end
      end
      first_error
    end

    def report_test_execution_error(error)
      error_message = normalized_error_message(error)
      $stderr.puts "An error occurred while executing test: #{error_message}"
      $stderr.puts error.backtrace.join("\n")
      @formatter.failure_result("Test failed at #{formatted_time} with error message: #{error_message}")
      @failed_count += 1
    end

    def report_context_execution_error(error, description:)
      error_message = normalized_error_message(error)
      $stderr.puts "An error occurred while executing context '#{description}': #{error_message}"
      $stderr.puts error.backtrace.join("\n")
      @formatter.failure_result("Context '#{description}' failed at #{formatted_time} with error message: #{error_message}")
      @failed_count += 1
    end

    def report_spec_source_execution_error(error, source_index:)
      error_message = normalized_error_message(error)
      $stderr.puts "An error occurred while loading spec source ##{source_index}: #{error_message}"
      $stderr.puts error.backtrace.join("\n")
      @formatter.failure_result("Spec source ##{source_index} failed at #{formatted_time} with error message: #{error_message}")
      @failed_count += 1
    end

    def normalized_error_message(error)
      error.message.to_s.gsub(/undefined method '([^']+)'/) { "undefined method `#{$1}'" }
    end

    def process_test_result(result)
      expectation_results = @current_expectation_results || []
      unless expectation_results.empty?
        failing_result = expectation_results.find { |expectation_result| !expectation_result.pass }
        result = failing_result || expectation_results.last
      end

      unless result.respond_to?(:pass)
        raise NoMethodError, 'Test example must return a matcher result. Use expect(...).to(...) or expect(...).not_to(...).'
      end

      if !result.pass
        @failed_count += 1
        @formatter.justification(result.comment) if result.comment
        @formatter.failure_result("Test failed at #{formatted_time}")
      else
        @passed_count += 1
        if @verbose
          @formatter.justification(result.comment) if result.comment
          @formatter.success_result("Test passed successfully at #{formatted_time}")
        end
      end
    end

    def build_expectation_failure_message(matcher, negated:)
      matcher_label, expected_value = matcher_sentence_parts_for_failure(matcher)
      message = +"Expect #{expectation_operand_text(@actual, label: @actual_label)}"
      message << (negated ? ' not to ' : ' to ')
      message << matcher_label

      unless expected_value.equal?(PrD::Formatters::Formatter::NO_EXPECTED_VALUE)
        expected_label = matcher.respond_to?(:expected_label) ? matcher.expected_label : nil
        message << " #{expectation_operand_text(expected_value, label: expected_label)}"
      end

      message
    end

    def matcher_sentence_parts_for_failure(matcher)
      return ['match', matcher.expected] unless @formatter.respond_to?(:matcher_sentence_parts, true)

      @formatter.send(:matcher_sentence_parts, matcher, sources: nil)
    rescue StandardError
      ['match', matcher.expected]
    end

    def expectation_operand_text(value, label:)
      value_text = expectation_value_text(value)
      return value_text if label.nil? || label.to_s.empty?

      "#{label} (=#{value_text})"
    end

    def expectation_value_text(value)
      return "(#{value.language} code)" if defined?(PrD::Code) && value.is_a?(PrD::Code)
      return value.inspect unless @formatter.respond_to?(:serialize, true)

      @formatter.send(:serialize, value).to_s
    rescue StandardError
      value.inspect
    end

    def merge_expectation_comments(failure_message, matcher_comment)
      return failure_message if matcher_comment.nil? || matcher_comment.to_s.strip.empty?

      "#{failure_message}. #{matcher_comment}"
    end

    def record_expectation_result(result)
      return if @current_expectation_results.nil?

      @current_expectation_results << result
    end

  end
end
