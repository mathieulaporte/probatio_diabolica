module PrD
  module Formatters
    class Formatter
      SUPPORTED_MODES = %i[verbose synthetic].freeze

      def initialize(io: $stdout, serializers: {}, mode: :verbose)
        @io = io
        @serializers = serializers
        @level = 0
        @mode = normalize_mode(mode)
        @current_test_title = nil
      end

      def title(message)
        raise NotImplementedError, "#{self.class} must implement #title"
      end

      def context(message)
        raise NotImplementedError, "#{self.class} must implement #context"
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

      def end_it(description = nil, &block)
        raise NotImplementedError, "#{self.class} must implement #end_it"
      end

      def justification(justification)
        raise NotImplementedError, "#{self.class} must implement #justification"
      end

      def subject(subject)
        raise NotImplementedError, "#{self.class} must implement #subject"
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

      def flush
        @io.flush
      end

      private

      def synthetic?
        @mode == :synthetic
      end

      def normalize_mode(mode)
        normalized = mode.to_sym
        return normalized if SUPPORTED_MODES.include?(normalized)

        raise ArgumentError, "Unsupported formatter mode: #{mode}. Supported: #{SUPPORTED_MODES.join(', ')}"
      end

      def serialize(value)
        serializer = @serializers[value.class]
        return serializer.call(value) if serializer
        return value.path if value.is_a?(File)
        return value.map { |v| serialize(v) } if value.is_a?(Array)
        return value.transform_values { |v| serialize(v) } if value.is_a?(Hash)

        value
      end

      def code_object?(value)
        defined?(PrD::Code) && value.is_a?(PrD::Code)
      end
    end
  end
end
