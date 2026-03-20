require 'tempfile'
require 'ruby_llm/schema'
require 'timeout'

module PrD
  module Matchers
    class LlmMatcher < Matcher
      DSL_HELPER_NAME = :satisfy
      DEFAULT_TIMEOUT_SECONDS = 30
      DEFAULT_RETRIES = 1
      SUPPORTED_IMAGE_EXTENSIONS = %w[.png .jpg .jpeg].freeze

      class TestResult < RubyLLM::Schema
        string :justification
        boolean :satisfy
      end

      def initialize(expected, client:, timeout_seconds: DEFAULT_TIMEOUT_SECONDS, retries: DEFAULT_RETRIES)
        @llm_client = client
        @timeout_seconds = timeout_seconds
        @retries = retries
        super(expected)
      end

      def matches?(actual)
        if actual.is_a?(String)
          return build_runtime_result(text(@expected, actual))
        elsif defined?(PrD::Code) && actual.is_a?(PrD::Code)
          return build_runtime_result(text(@expected, actual.source))
        elsif image_files_array?(actual)
          return build_runtime_result(images(@expected, actual))
        elsif file_like?(actual)
          if image_file?(actual)
            return build_runtime_result(images(@expected, [actual]))
          else
            content = actual.read
            actual.rewind if actual.respond_to?(:rewind)
            return build_runtime_result(text(@expected, content))
          end
        else
          raise ArgumentError, "Unsupported type for LLM matcher: #{actual.class}"
        end
      end

      private

      def build_runtime_result(llm_result)
        content = llm_result&.content
        unless content.is_a?(Hash) && content.key?('satisfy') && content.key?('justification')
          raise ArgumentError, 'Invalid LLM response format: expected JSON object with justification and satisfy'
        end

        PrD::Runtime::TestResult.new(comment: content['justification'], pass: !!content['satisfy'])
      end

      def ask_with_retry(*args, **kwargs)
        attempts = 0
        begin
          attempts += 1
          Timeout.timeout(@timeout_seconds) { @llm_client.ask(*args, **kwargs) }
        rescue Timeout::Error => e
          raise e if attempts > (@retries + 1)
          retry
        rescue StandardError => e
          raise e if attempts > (@retries + 1)
          retry
        end
      end

      def text(expected, actual)
        @llm_client
          .with_instructions(
            'You are an assistant that verifies conditions on text. Do not assume how things can be, use only what is provided. If multiple conditions are given they should all be true to pass satisfy to true. You will receive a text and a condition to check. First, provide your reasoning in the <justification> field. Then, indicate whether the condition is satisfied in the <satisfy> field, using either true or false.'
          )
          .with_params(response_format: { type: 'json_object' })
          .with_schema(TestResult)
        ask_with_retry("The current text : #{actual} \nDoes it satisfy the condition :\n\n#{expected}, respond in json ?")
      end

      def images(expected, actual_images)
        tempfiles = build_image_tempfiles(actual_images)

        @llm_client
          .with_instructions(
            'You are a helpful assistant that verifies conditions on images. Do not assume how things can be, use only what is provided. You will receive one or more images and a condition to check. First, provide your reasoning in the <justification> field. Then, indicate whether the condition is satisfied in the <satisfy> field, using either true or false.'
          )
          .with_params(response_format: { type: 'json_object' })
          .with_schema(TestResult)
        ask_with_retry("Do these images satisfy the condition :\n\n#{expected} ?\nRespond in json.", with: tempfiles.map(&:path))
      ensure
        tempfiles&.each(&:close!)
      end

      def build_image_tempfiles(actual_images)
        actual_images.map do |actual_image|
          actual_image.rewind if actual_image.respond_to?(:rewind)

          Tempfile.new(['image', File.extname(actual_image.path)]).tap do |tempfile|
            tempfile.binmode
            tempfile.write(actual_image.read)
            tempfile.rewind
          end
        ensure
          actual_image.rewind if actual_image.respond_to?(:rewind)
        end
      end

      def image_files_array?(value)
        value.is_a?(Array) && !value.empty? && value.all? { |entry| file_like?(entry) && image_file?(entry) }
      end

      def file_like?(value)
        value.is_a?(File) || value.is_a?(Tempfile)
      end

      def image_file?(file)
        SUPPORTED_IMAGE_EXTENSIONS.include?(File.extname(file.path).downcase)
      end
    end
  end
end
