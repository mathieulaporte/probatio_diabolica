require 'base64'
require 'tempfile'
require 'ruby_llm'
require 'ruby_llm/schema'

module PrD
  module Matchers
    class LlmMatcher < Matcher
      DSL_HELPER_NAME = :satisfy

      class TestResult < RubyLLM::Schema
        string :justification
        boolean :satisfy
      end

      def initialize(expected, client:)
        @llm_client = client
        super(expected)
      end

      def matches?(actual)
        if actual.is_a?(String)
          llm_result = text(@expected, actual)
          return(
            PrD::Runtime::TestResult.new(
              comment: llm_result.content['justification'],
              pass: llm_result.content['satisfy']
            )
          )
        elsif actual.is_a?(File)
          if actual.path.end_with?('.png', '.jpg', '.jpeg')
            llm_result = image(@expected, actual)
            return(
              PrD::Runtime::TestResult.new(
                comment: llm_result.content['justification'],
                pass: llm_result.content['satisfy']
              )
            )
          else
            content = actual.read
            actual.rewind
            llm_result = text(@expected, content)
            llm_result.content.strip.downcase == 'yes'
          end
        else
          raise ArgumentError, "Unsupported type for LLM matcher: #{actual.class}"
        end
      end

      private

      def text(expected, actual)
        @llm_client
          .with_instructions(
            'You are an assistant that verifies conditions on text. Do not assume how things can be, use only what is provided. If multiple conditions are given they should all be true to pass satisfy to true. You will receive a text and a condition to check. First, provide your reasoning in the <justification> field. Then, indicate whether the condition is satisfied in the <satisfy> field, using either true or false.'
          )
          .with_params(response_format: { type: 'json_object' })
          .with_schema(TestResult)
          .ask("The current text : #{actual} \nDoes it satisfy the condition :\n\n#{expected}, respond in json ?")
      end

      def image(expected, actual)
        Tempfile.create(['image', File.extname(actual.path)]) do |tempfile|
          tempfile.binmode
          tempfile.write(actual.read)
          tempfile.rewind
          actual.rewind

          @llm_client
            .with_instructions(
              'You are a helpful assistant that verifies conditions on images. You will receive an image and a condition to check. First, provide your reasoning in the <justification> field. Then, indicate whether the condition is satisfied in the <satisfy> field, using either true or false.'
            )
            .with_params(response_format: { type: 'json_object' })
            .with_schema(TestResult)
            .ask("Does this image satisfy the condition :\n\n#{expected} ?\nRespond in json.", with: tempfile.path)
        end
      end
    end
  end
end
