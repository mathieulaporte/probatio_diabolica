module LlmSpec
  module Matchers
    class Matcher
      attr_reader :expected

      def initialize(expected)
        @expected = expected
      end

      def matches?(actual)
        raise NotImplementedError, "#{self.class} must implement #matches?"
      end
    end
  end
end
