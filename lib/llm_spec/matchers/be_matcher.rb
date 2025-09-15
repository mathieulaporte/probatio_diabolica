module LlmSpec
  module Matchers
    class BeMatcher < Matcher
      DSL_HELPER_NAME = :be
      def matches?(actual)
        LlmSpec::Runtime::TestResult.new(comment: nil, pass: actual.equal?(@expected))
      end
    end
  end
end
