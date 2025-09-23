module PrD
  module Matchers
    class HaveMatcher < Matcher
      DSL_HELPER_NAME = :have
      def matches?(actual)
        PrD::Runtime::TestResult.new(comment: nil, pass: actual.include?(@expected))
      end
    end
  end
end
