module PrD
  class ReportCollector < PrD::Formatters::Formatter
    def initialize(io: $stdout, serializers: {}, mode: :verbose, display_adapters: {}, subject_display_strategy: :on_evaluation, eager_subject_display_strategy: :on_evaluation)
      super(io: io, serializers: serializers, mode: mode, display_adapters: display_adapters)
      @model = PrD::ReportModel.new
      @subject_display_strategy = subject_display_strategy
      @eager_subject_display_strategy = eager_subject_display_strategy
    end

    attr_reader :model

    def title(message)
      record(:title, snapshot(message))
    end

    def context(message)
      record(:context, snapshot(message))
    end

    def success_result(message)
      record(:success_result, snapshot(message))
    end

    def failure_result(message)
      record(:failure_result, snapshot(message))
    end

    def it(description = nil, &block)
      @current_test_title = description.to_s
      record(:it, snapshot(description))
    end

    def end_it(description = nil, &block)
      record(:end_it, snapshot(description))
    end

    def justification(justification)
      record(:justification, snapshot(justification))
    end

    def let(name_or_value, value = MISSING_VALUE)
      if value.equal?(MISSING_VALUE)
        record(:let, snapshot(name_or_value))
      else
        record(:let, snapshot(name_or_value), snapshot(value))
      end
    end

    def subject(subject)
      record(:subject, snapshot(subject))
    end

    def subject_display_strategy
      @subject_display_strategy
    end

    def eager_subject_display_strategy
      @eager_subject_display_strategy
    end

    def pending(description = nil)
      record(:pending, snapshot(description))
    end

    def expect(expectation, label: nil)
      record(:expect, snapshot(expectation), label: snapshot(label))
    end

    def to
      record(:to)
    end

    def not_to
      record(:not_to)
    end

    def matcher(matcher, sources: nil)
      record(:matcher, snapshot_matcher(matcher), sources: snapshot(sources))
    end

    def result(passed_count, failed_count)
      @model.summary = { passed: passed_count, failed: failed_count }
      record(:result, snapshot(passed_count), snapshot(failed_count))
    end

    def increment_level
      super
      record(:increment_level)
    end

    def decrement_level
      super
      record(:decrement_level)
    end

    def flush
      # Rendering happens later from the canonical model.
      @io.flush if @io.respond_to?(:flush)
    end

    private

    def record(name, *args, **kwargs)
      @model.add_event(name:, args:, kwargs:)
    end

    def snapshot(value)
      @model.snapshot(value)
    end

    def snapshot_matcher(matcher)
      clone =
        begin
          matcher.dup
        rescue StandardError
          matcher
        end

      if clone.instance_variable_defined?(:@expected)
        clone.instance_variable_set(:@expected, snapshot(clone.instance_variable_get(:@expected)))
      end

      if clone.respond_to?(:expected_label) && clone.respond_to?(:expected_label=)
        clone.expected_label = snapshot(clone.expected_label)
      end

      clone
    rescue StandardError
      matcher
    end
  end
end
