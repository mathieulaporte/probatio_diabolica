module PrD
  module Matchers
    class EqMatcher < Matcher
      DSL_HELPER_NAME = :eq
      def matches?(actual)
        PrD::Runtime::TestResult.new(comment: nil, pass: actual == @expected)
      end
    end
  end
end
