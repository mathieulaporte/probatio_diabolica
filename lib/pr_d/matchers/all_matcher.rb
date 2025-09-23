module PrD
  module Matchers
    class AllMatcher < Matcher
      DSL_HELPER_NAME = :all
      def matches?(actual)
        PrD::Runtime::TestResult.new(comment: nil, pass: actual.all?(&@expected))
      end
    end
  end
end
