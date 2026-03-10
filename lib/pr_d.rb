require 'zeitwerk'
require 'ruby_llm'
require 'prism'

module PrD
  LOADER = Zeitwerk::Loader.new
  LOADER.push_dir(File.join(__dir__, 'pr_d'), namespace: self)
  LOADER.setup

  class Runtime
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

    def describe(description, model: nil, &block)
      context(description, model: model, &block)
      @formatter.result(@passed_count, @failed_count)
    end

    def context(description, model: nil, &block)
      @formatter.context(description)
      @formatter.increment_level
      @models_stack.push(model) if model

      instance_eval(&block)

      @models_stack.pop if model
      @formatter.decrement_level
    end

    def it(description = nil, model = nil, &block)
      begin
        description ||= @tests.split("\n")[block.source_location.last - 1].strip
        @models_stack.push(model) if model
        @formatter.it(description, &block) if @verbose
        @formatter.increment_level
        result = block.call
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
        return result
      rescue => e
        $stderr.puts "An error occurred while executing test: #{e.message}"
        $stderr.puts e.backtrace.join("\n")
        @formatter.failure_result("Test failed at #{formatted_time} with error message: #{e.message}")
        @failed_count += 1
      ensure
        @formatter.end_it(description, &block)
        @formatter.decrement_level
        @models_stack.pop if model
      end
    end

    def let(name, &block)
      block_result = block.call

      @formatter.let(block_result) if @verbose

      instance_variable_set("@#{name}", block_result)
      define_singleton_method(name) { block_result }
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
        @subject = block.call
        @formatter.subject(@subject) if @verbose
      else
        @subject ||= nil
      end
      @subject
    end

    def source_code(class_or_method)
      if class_or_method.is_a?(Class)
        file, line = Object.const_source_location(class_or_method.to_s)
        return nil unless file

        code = File.read(file)
        tree = Prism.parse(code)
        extract_class_from_node(tree.value, class_or_method.to_s, code)
      else
        file, line = class_or_method.source_location
        return nil unless file && line

        code = File.read(file)
        tree = Prism.parse(code)
        extract_method_from_node(tree.value, class_or_method.name, code)
      end
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
        @formatter.expect('Le sujet')
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
      @formatter.flush
    end

    private

    def formatted_time
      Time.now.utc.strftime('%Y-%m-%d %H:%M:%S UTC')
    end

    def extract_method_from_node(node, method_name, code)
      return nil unless node.respond_to?(:child_nodes)

      node.child_nodes.each do |child|
        if child.is_a?(Prism::DefNode) && child.name.to_s == method_name.to_s
          return code[child.location.start_offset...child.location.end_offset]
        end

        found = extract_method_from_node(child, method_name, code)
        return found if found
      end

      nil
    end

    def extract_class_from_node(node, class_name, code)
      return nil unless node.respond_to?(:child_nodes)

      node.child_nodes.each do |child|
        if child.is_a?(Prism::ClassNode)
          path = child.constant_path&.slice
          if path == class_name.to_s.split('::').last
            return code[child.location.start_offset...child.location.end_offset]
          end
        end

        found = extract_class_from_node(child, class_name, code)
        return found if found
      end

      nil
    end
  end
end
