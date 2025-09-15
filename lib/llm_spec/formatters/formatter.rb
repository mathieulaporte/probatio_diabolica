module LlmSpec
  module Formatters
    class Formatter
      def initialize(io: $stdout, serializers: {})
        @io = io
        @serializers = serializers
        @level = 0
      end

      # Méthodes qui doivent être implémentées par les sous-classes
      def title(message)
        raise NotImplementedError, "#{self.class} must implement #title"
      end

      def success_result(message)
        raise NotImplementedError, "#{self.class} must implement #success_result"
      end

      def failure_result(message)
        raise NotImplementedError, "#{self.class} must implement #failure_result"
      end

      def it(description = nil, &block)
        raise NotImplementedError, "#{self.class} must implement #it"
      end

      def pending(description = nil)
        raise NotImplementedError, "#{self.class} must implement #pending"
      end

      def expect(expectation)
        raise NotImplementedError, "#{self.class} must implement #expect"
      end

      def to
        raise NotImplementedError, "#{self.class} must implement #to"
      end

      def not_to
        raise NotImplementedError, "#{self.class} must implement #not_to"
      end
      def matcher(matcher, sources: nil)
        raise NotImplementedError, "#{self.class} must implement #matcher"
      end

      def result(passed_count, failed_count)
        raise NotImplementedError, "#{self.class} must implement #result"
      end

      def increment_level
        @level += 1
      end

      def decrement_level
        @level -= 1
      end
    end
  end
end
