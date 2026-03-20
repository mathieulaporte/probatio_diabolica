module PrD
  module Matchers
    class LtMatcher < Matcher
      DSL_HELPER_NAME = :lt

      def matches?(actual)
        PrD::Runtime::TestResult.new(comment: nil, pass: actual < @expected)
      end
    end
  end
end
