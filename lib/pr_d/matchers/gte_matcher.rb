module PrD
  module Matchers
    class GteMatcher < Matcher
      DSL_HELPER_NAME = :gte

      def matches?(actual)
        PrD::Runtime::TestResult.new(comment: nil, pass: actual >= @expected)
      end
    end
  end
end
