require 'prawn'
require 'rouge'

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

      def initialize(io: $stdout, serializers: {}, mode: :verbose, display_adapters: {})
        super(io: io, serializers: serializers, mode: mode, display_adapters: display_adapters)
        @events = []
        @summary = { passed: 0, failed: 0 }
        @index_entries = []
        @anchor_counters = Hash.new(0)
        @pending_expectation = nil
      end

      def title(message)
        return if synthetic?
        add_event(:title, message:, level: @level)
      end

      def context(message)
        anchor_id = next_anchor_id('ctx')
        add_index_entry(type: :context, label: message, level: @level, anchor_id:)
        if synthetic?
          add_event(:anchor_marker, message: '', level: @level, anchor_id:)
          return
        end
        add_event(:context, message:, level: @level, anchor_id:)
      end

      def success_result(message)
        if synthetic?
          add_event(:success, message: @current_test_title.to_s, level: @level)
          return
        end
        add_event(:success, message:, level: @level)
      end

      def failure_result(message)
        if synthetic?
          add_event(:failure, message: @current_test_title.to_s, level: @level)
          return
        end
        add_event(:failure, message:, level: @level)
      end

      def it(description = nil, &block)
        @current_test_title = description.to_s
        @pending_expectation = nil
        anchor_id = next_anchor_id('test')
        add_index_entry(type: :test, label: description.to_s, level: @level, anchor_id:)
        add_event(:it, message: description.to_s, level: @level, anchor_id:)
      end

      def end_it(description = nil, &block)
      end

      def justification(justification)
        return if synthetic?
        add_event(:justification, message: "Justification: #{justification}", level: @level + 1)
      end

      def let(name_or_value, value = MISSING_VALUE)
        return if synthetic?
        name, rendered_value = named_value_arguments(name_or_value, value)
        label = name.nil? ? 'Let' : "Let(:#{name})"
        add_event(:subject, message: label, level: @level)
        append_subject_node(display_node(rendered_value), level: @level + 1)
      end

      def subject(subject)
        return if synthetic?
        add_event(:subject, message: 'Subject', level: @level)
        append_subject_node(display_node(subject), level: @level + 1)
      end

      def subject_display_strategy
        :on_evaluation
      end

      def eager_subject_display_strategy
        :on_definition
      end

      def pending(description = nil)
        pending_label = description || 'Pending test'
        anchor_id = next_anchor_id('pending')
        add_index_entry(type: :pending, label: pending_label, level: @level, anchor_id:)
        add_event(:pending, message: pending_label, level: @level, anchor_id:)
        return if synthetic?
        add_event(:detail, message: 'This test is pending and has not been executed.', level: @level + 1)
      end

      def expect(expectation, label: nil)
        return if synthetic?
        @pending_expectation = { actual: expectation, actual_label: label, operator: :to }
      end

      def to
        return if synthetic?
        @pending_expectation ||= {}
        @pending_expectation[:operator] = :to
      end

      def not_to
        return if synthetic?
        @pending_expectation ||= {}
        @pending_expectation[:operator] = :not_to
      end

      def matcher(matcher, sources: nil)
        return if synthetic?
        matcher_label, expected_value = matcher_sentence_parts(matcher, sources:)
        expected_label = matcher.respond_to?(:expected_label) ? matcher.expected_label : nil
        add_expectation_sentence_event(matcher_label, expected_value, expected_label:)
      ensure
        @pending_expectation = nil
      end

      def result(passed_count, failed_count)
        @summary = { passed: passed_count, failed: failed_count }
        add_event(:result, message: "#{passed_count} passed, #{failed_count} failed", level: 0)
      end

      def flush
        document = Prawn::Document.new(page_size: 'A4', margin: 42)
        render_header(document)
        render_index(document)
        render_events(document)
        render_summary(document)

        @io.binmode if @io.respond_to?(:binmode)
        @io.write(document.render)
        super
      end

      private

      def add_event(type, message:, level:, anchor_id: nil, **extra)
        @events << {
          type:,
          message: safe_pdf_text(message.to_s),
          level: [level, 0].max,
          anchor_id:
        }.merge(extra)
      end

      def add_index_entry(type:, label:, level:, anchor_id:)
        @index_entries << {
          type:,
          label: safe_pdf_text(label.to_s),
          level: [level, 0].max,
          anchor_id:
        }
      end

      def safe_pdf_text(text)
        text
          .encode('Windows-1252', invalid: :replace, undef: :replace, replace: '?')
          .encode('UTF-8')
      end

      def rouge_lexer_for(source, language)
        Rouge::Lexer.find_fancy(language.to_s, source.to_s) || Rouge::Lexers::PlainText
      rescue StandardError
        Rouge::Lexers::PlainText
      end

      def rouge_token_color(token)
        qualname = token.qualname.to_s

        return '6B7280' if qualname.start_with?('Comment')
        return 'C2410C' if qualname.start_with?('Keyword', 'Operator')
        return '1D4ED8' if qualname.start_with?('Name.Function', 'Name.Class', 'Name.Builtin')
        return '047857' if qualname.start_with?('Literal.String')
        return '7C3AED' if qualname.start_with?('Literal.Number')

        COLORS[:text]
      end

      def highlighted_code_fragments(source, language)
        lexer = rouge_lexer_for(source, language)
        fragments = lexer.lex(source.to_s).filter_map do |token, value|
          next if value.nil? || value.empty?

          {
            text: safe_pdf_text(value),
            color: rouge_token_color(token),
            font: 'Courier'
          }
        end

        return fragments unless fragments.empty?

        [{ text: safe_pdf_text(source.to_s), color: COLORS[:text], font: 'Courier' }]
      rescue StandardError
        [{ text: safe_pdf_text(source.to_s), color: COLORS[:text], font: 'Courier' }]
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

      def render_index(document)
        return if @index_entries.empty?

        document.fill_color COLORS[:title]
        document.text 'Index', size: 14, style: :bold
        document.move_down 4

        @index_entries.each do |entry|
          document.indent(entry[:level] * 12) do
            document.formatted_text(
              [
                {
                  text: "- #{index_label(entry)}",
                  anchor: entry[:anchor_id],
                  styles: [:underline],
                  color: COLORS[:context]
                }
              ],
              size: 10
            )
          end
          document.move_down 1
        end

        document.move_down 8
        document.stroke_color COLORS[:border]
        document.stroke_horizontal_rule
        document.stroke_color '000000'
        document.move_down 8
      end

      def render_events(document)
        @events.each do |event|
          register_anchor(document, event)
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
          when :expectation
            render_expectation_event(document, event)
          when :code_header
            styled_line(document, event[:message], level: event[:level], size: 10, style: :bold, color: COLORS[:muted])
          when :code_block
            render_code_block(document, event[:message], level: event[:level], language: event[:language])
          when :detail, :subject, :justification
            styled_line(document, event[:message], level: event[:level], size: 10, color: COLORS[:text])
          when :subject_image
            render_image(document, event[:message], level: event[:level])
          when :anchor_marker
            next
          when :result
            document.move_down 8
            styled_line(document, event[:message], level: event[:level], size: 11, style: :bold, color: COLORS[:title])
          end
        end
      end

      def register_anchor(document, event)
        anchor_id = event[:anchor_id]
        return if anchor_id.nil?

        document.add_dest(anchor_id, document.dest_xyz(0, document.cursor))
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

      def render_code_block(document, text, level:, language: nil)
        document.indent(level * 14) do
          document.fill_color COLORS[:muted]
          document.text '--- Code Block ---', size: 9, style: :italic
          document.formatted_text(highlighted_code_fragments(text, language), size: 9)
          document.fill_color COLORS[:muted]
          document.text '--- End Block ---', size: 9, style: :italic
          document.fill_color COLORS[:text]
        end
        document.move_down 3
      end

      def render_expectation_event(document, event)
        fragments = event[:fragments] || []
        return if fragments.empty?

        document.indent(event[:level] * 14) do
          document.formatted_text(fragments, size: 10)
        end
        document.move_down 2
      end

      def add_expectation_sentence_event(matcher_label, expected_value, expected_label: nil)
        actual_provided = @pending_expectation && @pending_expectation.key?(:actual)
        actual = actual_provided ? @pending_expectation[:actual] : nil
        operator = expectation_operator_text(@pending_expectation && @pending_expectation[:operator])
        actual_label = actual_provided ? @pending_expectation[:actual_label] : nil
        actual_text = actual_provided ? (actual_label || expectation_inline_value(actual)) : '(subject)'
        expected_present = !expected_value.equal?(NO_EXPECTED_VALUE)
        expected_text = expected_present ? (expected_label || expectation_inline_value(expected_value)) : nil

        fragments = [
          expectation_keyword_fragment('Expect'),
          expectation_plain_fragment(' '),
          expectation_value_fragment(actual_text, role: :actual),
          expectation_plain_fragment(" #{operator} "),
          expectation_keyword_fragment(matcher_label)
        ]
        if expected_present
          fragments << expectation_plain_fragment(' ')
          fragments << expectation_value_fragment(expected_text, role: :expected)
        end

        add_event(:expectation, message: '', level: @level + 1, fragments:)
        add_expectation_code_event('Actual', actual, level: @level + 2)
        add_expectation_code_event('Expected', expected_value, level: @level + 2) if expected_present
      end

      def expectation_inline_value(value)
        return "(#{value.language} code)" if code_object?(value)

        serialize(value).to_s
      end

      def expectation_plain_fragment(text)
        { text: safe_pdf_text(text), color: COLORS[:text] }
      end

      def expectation_keyword_fragment(text)
        { text: safe_pdf_text(text), styles: [:bold], color: COLORS[:title] }
      end

      def expectation_value_fragment(text, role:)
        color = role == :expected ? COLORS[:pass] : COLORS[:context]
        { text: safe_pdf_text(text), color:, font: 'Courier' }
      end

      def add_expectation_code_event(prefix, value, level:)
        return unless code_object?(value)

        add_event(:code_header, message: "#{prefix} code (#{value.language})", level:)
        add_event(:code_block, message: value.source, level:, language: value.language)
      end

      def index_label(entry)
        prefix =
          case entry[:type]
          when :context then 'Context'
          when :pending then 'Pending'
          else 'Test'
          end

        "#{prefix}: #{entry[:label]}"
      end

      def next_anchor_id(prefix)
        @anchor_counters[prefix] += 1
        "#{prefix}-#{@anchor_counters[prefix]}"
      end

      def append_subject_node(node, level:, key_label: nil)
        add_event(:detail, message: "#{key_label}:", level:) unless key_label.nil?
        target_level = key_label.nil? ? level : level + 1

        case node[:type]
        when :code
          add_event(:code_header, message: "Language: #{node[:language]}", level: target_level)
          add_event(:code_block, message: node[:source], level: target_level, language: node[:language])
        when :map
          entries = node[:entries] || []
          if entries.empty?
            add_event(:detail, message: '{}', level: target_level)
            return
          end

          entries.each do |entry|
            append_subject_node(entry[:value], level: target_level, key_label: entry[:label].to_s)
          end
        when :list
          items = node[:items] || []
          if items.empty?
            add_event(:detail, message: '[]', level: target_level)
            return
          end

          items.each_with_index do |entry, index|
            append_subject_node(entry, level: target_level, key_label: "[#{index}]")
          end
        when :image
          add_event(:detail, message: "Image file: #{node[:path]}", level: target_level)
          add_event(:subject_image, message: node[:path], level: target_level)
        when :pdf_file
          add_event(:detail, message: "PDF file: #{node[:path]}", level: target_level)
        when :pdf_reader
          add_event(:detail, message: 'PDF::Reader value', level: target_level)
        else
          add_event(:detail, message: node[:text].to_s, level: target_level)
        end
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
