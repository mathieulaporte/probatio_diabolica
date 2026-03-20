module PrD
  module Matchers
    class LteMatcher < Matcher
      DSL_HELPER_NAME = :lte

      def matches?(actual)
        PrD::Runtime::TestResult.new(comment: nil, pass: actual <= @expected)
      end
    end
  end
end
