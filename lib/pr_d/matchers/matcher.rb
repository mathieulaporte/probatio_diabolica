module PrD
  module Matchers
    class Matcher
      attr_reader :expected
      attr_accessor :expected_label

      def initialize(expected)
        @expected = expected
        @expected_label = nil
      end

      def matches?(actual)
        raise NotImplementedError, "#{self.class} must implement #matches?"
      end
    end
  end
end
