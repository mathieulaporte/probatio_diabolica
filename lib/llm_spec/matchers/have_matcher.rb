module LlmSpec
  module Matchers
    class HaveMatcher < Matcher
      DSL_HELPER_NAME = :have
      def matches?(actual)
        LlmSpec::Runtime::TestResult.new(comment: nil, pass: actual.include?(@expected))
      end
    end
  end
end
