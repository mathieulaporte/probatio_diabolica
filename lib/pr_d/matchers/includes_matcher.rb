module PrD
  module Matchers
    class IncludesMatcher < Matcher
      DSL_HELPER_NAME = :includes
      def matches?(actual)
        if actual.is_a?(String) || actual.is_a?(Array)
          PrD::Runtime::TestResult.new(comment: nil, pass: actual.include?(@expected))
        elsif actual.is_a?(File)
          content = actual.read
          actual.rewind
          PrD::Runtime::TestResult.new(comment: nil, pass: content.include?(@expected))
        elsif actual.is_a?(PDF::Reader)
          PrD::Runtime::TestResult.new(comment: nil, pass: actual.pages.any? { |page| page.text.include?(@expected) })
        else
          raise ArgumentError, "Unsupported type for includes matcher: #{actual.class}"
        end
      end
    end
  end
end
