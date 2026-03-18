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
      PrD::Matchers::EqMatcher,
      PrD::Matchers::HaveMatcher,
      PrD::Matchers::IncludesMatcher,
      PrD::Matchers::LlmMatcher
    ].freeze

    def initialize(output_dir:, formatter: nil, matchers: [], verbose: true, config_file: nil)
      @actual = nil
      @passed_count = 0
      @failed_count = 0
      @formatter = formatter || PrD::Formatters::SimpleFormatter.new
      @output_dir = output_dir
      @verbose = verbose
      (DEFAULT_MATCHERS + matchers).each do |matcher|
        define_singleton_method(matcher::DSL_HELPER_NAME) do |*args|
          if matcher == PrD::Matchers::LlmMatcher
            model = current_model
            raise ArgumentError, 'LLM matcher requires a model. Set model: on context/it before using satisfy().' if model.nil?

            begin
              matcher.new(*args, client: RubyLLM.chat(model: model))
            rescue StandardError => e
              raise ArgumentError, "Unable to initialize LLM client for model '#{model}': #{e.message}"
            end
          else
            matcher.new(*args)
          end
        end
      end
      @models_stack = []
      @hook_scopes = [{ before: [], after: [] }]
      @subject_definition_stack = [nil]
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
      @formatter.context(description)
      @formatter.increment_level
      @models_stack.push(model) if model
      @hook_scopes << { before: [], after: [] }
      @subject_definition_stack << @subject_definition_stack.last

      instance_eval(&block)
    ensure
      @subject_definition_stack.pop
      @hook_scopes.pop
      @models_stack.pop if model
      @formatter.decrement_level
    end

    def it(description = nil, model = nil, &block)
      result = nil
      execution_error = nil
      before_hooks = collect_before_hooks
      after_hooks = collect_after_hooks

      begin
        description ||= @tests.split("\n")[block.source_location.last - 1].strip
        @models_stack.push(model) if model
        @formatter.it(description, &block) if @verbose
        @formatter.increment_level
        reset_subject_memoization!

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
        reset_subject_memoization!
      end

      result
    end

    def let(name, &block)
      block_result = block.call

      if @verbose
        formatter_let_arity = @formatter.method(:let).arity
        if formatter_let_arity == 1
          @formatter.let(block_result)
        else
          @formatter.let(name, block_result)
        end
      end

      instance_variable_set("@#{name}", block_result)
      define_singleton_method(name) { block_result }
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
      matcher.matches?(@actual)
    end

    def not_to(matcher)
      @formatter.not_to
      @formatter.matcher(matcher)
      result = matcher.matches?(@actual)
      TestResult.new(comment: result.comment, pass: !result.pass)
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
      if @verbose && @formatter.eager_subject_display_strategy == :on_definition
        @formatter.subject(instance_eval(&block))
      end
      render_in_before = @verbose && @formatter.eager_subject_display_strategy == :on_evaluation
      before { evaluate_subject_value(render: render_in_before) }
      nil
    end

    def expect(*args, &block)
      if args.length >= 1
        @actual = args.first
        @formatter.expect(@actual)
      elsif block_given?
        @actual = block.call(subject)
        @formatter.expect(@actual)
      else
        @actual = subject
        @formatter.expect(@actual)
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
      @tests.each { |test| instance_eval(test) }
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
      $stderr.puts "An error occurred while executing test: #{error.message}"
      $stderr.puts error.backtrace.join("\n")
      @formatter.failure_result("Test failed at #{formatted_time} with error message: #{error.message}")
      @failed_count += 1
    end

    def process_test_result(result)
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

  end
end
