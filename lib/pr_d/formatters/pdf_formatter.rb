require 'prawn'

module PrD
  module Formatters
    class PdfFormatter < Formatter
      COLORS = {
        text: '1F2937',
        muted: '6B7280',
        title: '0F172A',
        context: '1D4ED8',
        pass: '166534',
        fail: '991B1B',
        pending: '92400E',
        border: 'E5E7EB'
      }.freeze

      def initialize(io: $stdout, serializers: {})
        super(io: io, serializers: serializers)
        @events = []
        @summary = { passed: 0, failed: 0 }
      end

      def title(message)
        add_event(:title, message:, level: @level)
      end

      def context(message)
        add_event(:context, message:, level: @level)
      end

      def success_result(message)
        add_event(:success, message:, level: @level)
      end

      def failure_result(message)
        add_event(:failure, message:, level: @level)
      end

      def it(description = nil, &block)
        add_event(:it, message: description.to_s, level: @level)
      end

      def end_it(description = nil, &block)
      end

      def justification(justification)
        add_event(:justification, message: "Justification: #{justification}", level: @level + 1)
      end

      def let(value)
      end

      def subject(subject)
        add_event(:subject, message: 'Subject', level: @level)
        if image_file?(subject)
          add_event(:detail, message: serialize(subject).to_s, level: @level + 1)
          add_event(:subject_image, message: subject.path, level: @level + 1)
        else
          add_event(:detail, message: serialize(subject).to_s, level: @level + 1)
        end
      end

      def pending(description = nil)
        add_event(:pending, message: (description || 'Pending test'), level: @level)
        add_event(:detail, message: 'This test is pending and has not been executed.', level: @level + 1)
      end

      def expect(expectation)
        add_event(:detail, message: "Expect: #{serialize(expectation)}", level: @level + 1)
      end

      def to
        add_event(:detail, message: 'To:', level: @level + 1)
      end

      def not_to
        add_event(:detail, message: 'Not to:', level: @level + 1)
      end

      def matcher(matcher, sources: nil)
        case matcher
        when Matchers::EqMatcher
          add_event(:matcher, message: "Be equal to: #{serialize(matcher.expected)}", level: @level + 2)
        when Matchers::BeMatcher
          add_event(:matcher, message: "Be the same object as: #{serialize(matcher.expected)}", level: @level + 2)
        when Matchers::IncludesMatcher
          add_event(:matcher, message: "Include: #{serialize(matcher.expected)}", level: @level + 2)
        when Matchers::HaveMatcher
          add_event(:matcher, message: "Have: #{serialize(matcher.expected)}", level: @level + 2)
        when Matchers::LlmMatcher
          add_event(:matcher, message: "Satisfy condition: #{serialize(matcher.expected)}", level: @level + 2)
        when Matchers::AllMatcher
          add_event(:matcher, message: 'all match the given condition', level: @level + 2)
        else
          add_event(:matcher, message: "match: #{matcher.class}", level: @level + 2)
        end
      end

      def result(passed_count, failed_count)
        @summary = { passed: passed_count, failed: failed_count }
        add_event(:result, message: "#{passed_count} passed, #{failed_count} failed", level: 0)
      end

      def flush
        document = Prawn::Document.new(page_size: 'A4', margin: 42)
        render_header(document)
        render_events(document)
        render_summary(document)

        @io.binmode if @io.respond_to?(:binmode)
        @io.write(document.render)
        super
      end

      private

      def add_event(type, message:, level:)
        @events << { type:, message: safe_pdf_text(message.to_s), level: [level, 0].max }
      end

      def safe_pdf_text(text)
        text
          .encode('Windows-1252', invalid: :replace, undef: :replace, replace: '?')
          .encode('UTF-8')
      end

      def render_header(document)
        document.fill_color COLORS[:title]
        document.text 'Probatio Diabolica', size: 20, style: :bold
        document.text 'Test Report', size: 12, style: :italic, color: COLORS[:muted]
        document.move_down 6
        document.stroke_color COLORS[:border]
        document.stroke_horizontal_rule
        document.stroke_color '000000'
        document.move_down 10
      end

      def render_events(document)
        @events.each do |event|
          case event[:type]
          when :title, :context
            styled_line(document, event[:message], level: event[:level], size: 14, style: :bold, color: COLORS[:context], spacing: 6)
          when :it
            styled_line(document, event[:message], level: event[:level], size: 12, style: :bold, color: COLORS[:title], spacing: 4)
          when :success
            status_line(document, 'PASS', event[:message], event[:level], COLORS[:pass])
          when :failure
            status_line(document, 'FAIL', event[:message], event[:level], COLORS[:fail])
          when :pending
            status_line(document, 'PENDING', event[:message], event[:level], COLORS[:pending])
          when :matcher
            styled_line(document, event[:message], level: event[:level], size: 10, color: COLORS[:muted])
          when :detail, :subject, :justification
            styled_line(document, event[:message], level: event[:level], size: 10, color: COLORS[:text])
          when :subject_image
            render_image(document, event[:message], level: event[:level])
          when :result
            document.move_down 8
            styled_line(document, event[:message], level: event[:level], size: 11, style: :bold, color: COLORS[:title])
          end
        end
      end

      def render_summary(document)
        document.move_down 10
        document.stroke_color COLORS[:border]
        document.stroke_horizontal_rule
        document.stroke_color '000000'
        document.move_down 8

        color = @summary[:failed].positive? ? COLORS[:fail] : COLORS[:pass]
        document.fill_color color
        document.text "Summary: #{@summary[:passed]} passed, #{@summary[:failed]} failed", size: 12, style: :bold
        document.fill_color COLORS[:muted]
        document.text "Generated at #{Time.now.utc.strftime('%Y-%m-%d %H:%M:%S UTC')}", size: 9
        document.fill_color COLORS[:text]
      end

      def styled_line(document, text, level:, size:, color:, style: nil, spacing: 2)
        document.indent(level * 14) do
          document.fill_color color
          document.text text, size: size, style: style
          document.fill_color COLORS[:text]
        end
        document.move_down spacing
      end

      def status_line(document, badge, message, level, color)
        document.indent(level * 14) do
          document.formatted_text(
            [
              { text: "[#{badge}] ", styles: [:bold], color: color },
              { text: message, color: COLORS[:text] }
            ],
            size: 10
          )
        end
        document.move_down 2
      end

      def image_file?(value)
        value.is_a?(File) && value.path.match?(/\.(png|jpe?g)\z/i)
      end

      def render_image(document, path, level:)
        return unless File.exist?(path)

        document.indent(level * 14) do
          width = [document.bounds.width, 420].min
          document.image(path, fit: [width, 320], position: :center)
        end
        document.move_down 6
      rescue StandardError
        styled_line(document, "Unable to render image: #{path}", level: level, size: 9, color: COLORS[:fail])
      end
    end
  end
end
