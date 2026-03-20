module PrD
  module Matchers
    class GtMatcher < Matcher
      DSL_HELPER_NAME = :gt

      def matches?(actual)
        PrD::Runtime::TestResult.new(comment: nil, pass: actual > @expected)
      end
    end
  end
end
