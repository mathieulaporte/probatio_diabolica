module PrD
  module Matchers
    class EmptyMatcher < Matcher
      DSL_HELPER_NAME = :empty

      def initialize
        super(nil)
      end

      def matches?(actual)
        PrD::Runtime::TestResult.new(comment: nil, pass: actual.empty?)
      end
    end
  end
end
