require 'cgi'
require 'base64'
require 'rouge'

module PrD
  module Formatters
    class HtmlFormatter < Formatter
      def initialize(io: $stdout, serializers: {}, mode: :verbose)
        super(io: io, serializers: serializers, mode: mode)
        @content = +''
        @index_entries = []
        @anchor_counters = Hash.new(0)
        @rouge_formatter = Rouge::Formatters::HTMLLegacy.new(css_class: 'highlight')
      end

      def context(message)
        anchor_id = next_anchor_id('ctx')
        add_index_entry(type: :context, label: message, level: @level, anchor_id:)
        @content << "<h2 class=\"context\" id=\"#{anchor_id}\">#{escape(message)}</h2>"
      end

      def success_result(message)
        if synthetic?
          @content << "<div class='status success'>PASS</div>"
          return
        end
        @content << "<div class='status success'>✓ #{escape(message)}</div>"
      end

      def failure_result(message)
        if synthetic?
          @content << "<div class='status failure'>FAIL</div>"
          return
        end
        @content << "<div class='status failure'>✗ #{escape(message)}</div>"
      end

      def it(description = nil, &block)
        @current_test_title = description.to_s
        anchor_id = next_anchor_id('test')
        add_index_entry(type: :test, label: description.to_s, level: @level, anchor_id:)
        @content << "<article class=\"test-card\" id=\"#{anchor_id}\">"
        @content << "<h3 class=\"test-title\">#{escape(description)}</h3>"
      end

      def end_it(description = nil, &block)
        @content << '</article>'
      end

      def justification(justification)
        return if synthetic?
        @content << "<p class=\"line\"><strong>Justification:</strong> #{escape(justification)}</p>"
      end

      def let(value)
        return if synthetic?
        render_value_block('Let', value)
      end

      def subject(subject)
        return if synthetic?
        render_value_block('Subject', subject)
      end

      def pending(description = nil)
        pending_label = description || 'Pending test'
        anchor_id = next_anchor_id('pending')
        add_index_entry(type: :pending, label: pending_label, level: @level, anchor_id:)

        @content << "<article class=\"test-card\" id=\"#{anchor_id}\">"
        @content << "<h3 class=\"test-title\">#{escape(pending_label)}</h3>"
        if synthetic?
          @content << "<div class='status pending'>PENDING</div>"
        else
          @content << "<div class='status pending'>⚠ #{escape(pending_label)}</div>"
          @content << '<p class="line muted">This test is pending and has not been executed.</p>'
        end
        @content << '</article>'
      end

      def expect(expectation)
        return if synthetic?
        render_labeled_value('Expect', expectation)
      end

      def to
        return if synthetic?
        @content << '<p class="line"><strong>To:</strong></p>'
      end

      def not_to
        return if synthetic?
        @content << '<p class="line"><strong>Not to:</strong></p>'
      end

      def matcher(matcher, sources: nil)
        return if synthetic?
        case matcher
        when Matchers::EqMatcher
          render_matcher_value('Be equal to', matcher.expected)
        when Matchers::BeMatcher
          render_matcher_value('Be the same object as', matcher.expected)
        when Matchers::IncludesMatcher
          render_matcher_value('Include', matcher.expected)
        when Matchers::HaveMatcher
          render_matcher_value('Have', matcher.expected)
        when Matchers::LlmMatcher
          render_matcher_value('Satisfy condition', matcher.expected)
        when Matchers::AllMatcher
          if sources
            code_line = matcher.expected.source_location.last.to_i
            code = sources.lines[code_line - 1]
            @content << "<p class=\"line\"><strong>Matcher:</strong> All match condition #{escape(code.strip)}</p>"
          else
            @content << '<p class="line"><strong>Matcher:</strong> All match the given condition</p>'
          end
        else
          @content << "<p class=\"line\"><strong>Matcher:</strong> #{escape(matcher.class.to_s)}</p>"
        end
      end

      def result(passed_count, failed_count)
        summary_class = failed_count > 0 ? 'failure' : 'success'
        @content << "<p class='result #{summary_class}'><strong>#{passed_count} passed, #{failed_count} failed</strong></p>"
      end

      def flush
        @io << document_opening
        @io << render_index
        @io << @content
        @io << '</main></body></html>'
        super
      end

      private

      def document_opening
        <<~HTML
          <html>
            <head>
              <meta charset="utf-8" />
              <meta name="viewport" content="width=device-width, initial-scale=1" />
              <link rel="preconnect" href="https://fonts.googleapis.com">
              <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
              <link href="https://fonts.googleapis.com/css2?family=Saira:ital,wght@0,100..900;1,100..900&display=swap" rel="stylesheet">
              <style>
                :root {
                  --bg: #f3f4f6;
                  --paper: #ffffff;
                  --ink: #1f2937;
                  --muted: #6b7280;
                  --line: #e5e7eb;
                  --accent: #0f766e;
                  --sidebar-width: 320px;
                  --pass-bg: #ecfdf5;
                  --pass-fg: #166534;
                  --fail-bg: #fef2f2;
                  --fail-fg: #991b1b;
                  --pending-bg: #fff7ed;
                  --pending-fg: #9a3412;
                }

                * { box-sizing: border-box; }
                body {
                  margin: 0;
                  background: var(--bg);
                  color: var(--ink);
                  font-family: "Source Sans 3", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
                  line-height: 1.45;
                }

                main.container {
                  width: min(960px, 100% - 2rem);
                  margin: 2rem auto 3rem;
                  padding: 1.2rem;
                  background: #f9fafb;
                  border: 1px solid #e5e7eb;
                  border-radius: 18px;
                }

                body.has-index main.container {
                  width: min(960px, calc(100% - var(--sidebar-width) - 4rem));
                  margin: 1rem 1rem 2rem calc(var(--sidebar-width) + 2rem);
                }

                body.has-index.index-collapsed main.container {
                  width: min(960px, calc(100% - 2rem));
                  margin: 1rem auto 2rem;
                }

                .index-toggle {
                  position: fixed;
                  top: 0.9rem;
                  left: 0.9rem;
                  z-index: 1100;
                  border: 1px solid #d1d5db;
                  border-radius: 999px;
                  background: var(--paper);
                  color: #0f172a;
                  padding: 0.45rem 0.8rem;
                  font-size: 0.9rem;
                  font-weight: 600;
                  cursor: pointer;
                  box-shadow: 0 6px 18px rgba(15, 23, 42, 0.12);
                }

                .report-index {
                  position: fixed;
                  top: 3.2rem;
                  left: 1rem;
                  bottom: 1rem;
                  z-index: 1000;
                  width: var(--sidebar-width);
                  background: var(--paper);
                  border: 1px solid var(--line);
                  border-radius: 14px;
                  padding: 0.9rem 1rem;
                  overflow-y: auto;
                  transition: transform 0.18s ease, opacity 0.18s ease;
                }

                body.has-index.index-collapsed .report-index {
                  transform: translateX(calc(-1 * (var(--sidebar-width) + 1rem)));
                  opacity: 0;
                  pointer-events: none;
                }

                .index-title {
                  margin: 0 0 0.6rem;
                  font-family: "Saira", Georgia, serif;
                  font-size: 1.15rem;
                }

                .index-list {
                  margin: 0;
                  padding: 0;
                  list-style: none;
                }

                .index-item {
                  margin: 0.2rem 0;
                  padding-left: calc(var(--index-level, 0) * 1rem);
                }

                .index-link {
                  display: block;
                  white-space: nowrap;
                  overflow: hidden;
                  text-overflow: ellipsis;
                  color: var(--accent);
                  text-decoration: none;
                }

                .index-link:hover {
                  text-decoration: underline;
                }

                .context {
                  font-family: "Saira", Georgia, serif;
                  font-size: clamp(1.4rem, 2.8vw, 2rem);
                  margin: 1.3rem 0 1rem;
                  padding-bottom: 0.45rem;
                  border-bottom: 2px solid var(--line);
                }

                .test-card {
                  background: var(--paper);
                  border: 1px solid var(--line);
                  border-radius: 16px;
                  padding: 1rem 1.1rem;
                  margin: 0 0 1rem;
                  box-shadow: 0 8px 22px rgba(15, 23, 42, 0.06);
                }

                .test-title {
                  margin: 0 0 0.75rem;
                  font-family: "Saira", Georgia, serif;
                  font-size: 1.2rem;
                }

                .line {
                  margin: 0.38rem 0;
                  color: var(--ink);
                }

                .line strong {
                  color: #0f172a;
                  margin-right: 0.35rem;
                }

                .status {
                  margin: 0.7rem 0 0.2rem;
                  padding: 0.55rem 0.7rem;
                  border-radius: 10px;
                  font-weight: 600;
                }

                .status.success {
                  background: var(--pass-bg);
                  color: var(--pass-fg);
                }

                .status.failure {
                  background: var(--fail-bg);
                  color: var(--fail-fg);
                }

                .status.pending {
                  background: var(--pending-bg);
                  color: var(--pending-fg);
                }

                .subject-block {
                  margin: 0.5rem 0 0.75rem;
                  padding: 0.75rem;
                  border: 1px dashed #cbd5e1;
                  border-radius: 12px;
                  background: #f8fafc;
                }

                .nested-key {
                  margin: 0.32rem 0 0.15rem;
                  padding-left: calc(var(--nest-depth, 0) * 1rem);
                }

                .nested-value {
                  margin: 0.22rem 0 0.5rem;
                  padding-left: calc(var(--nest-depth, 0) * 1rem);
                }

                .nested-block {
                  margin-left: calc(var(--nest-depth, 0) * 1rem);
                }

                .subject-image {
                  margin-top: 0.55rem;
                  display: block;
                  margin-left: auto;
                  margin-right: auto;
                  max-width: min(100%, 640px);
                  height: auto;
                  border-radius: 10px;
                  border: 1px solid #d1d5db;
                }

                .subject-pdf {
                  margin-top: 0.65rem;
                  display: block;
                  width: min(100%, 760px);
                  height: 540px;
                  margin-left: auto;
                  margin-right: auto;
                  border-radius: 10px;
                  border: 1px solid #d1d5db;
                  background: #fff;
                }

                .result {
                  margin-top: 1.5rem;
                  padding: 0.9rem 1rem;
                  border-radius: 12px;
                  border: 1px solid var(--line);
                  background: #fff;
                  font-size: 1.05rem;
                }

                .result.success { color: var(--pass-fg); background: var(--pass-bg); }
                .result.failure { color: var(--fail-fg); background: var(--fail-bg); }
                .muted { color: var(--muted); }

                .code-language {
                  color: var(--muted);
                  font-size: 0.85rem;
                  text-transform: uppercase;
                  letter-spacing: 0.05em;
                }

                .code-block {
                  margin: 0.45rem 0 0.7rem;
                  border: 1px solid var(--line);
                  border-radius: 10px;
                  background: #fff;
                }

                .code-toggle {
                  list-style: none;
                  cursor: pointer;
                  padding: 0.6rem 0.8rem;
                  display: flex;
                  align-items: center;
                  justify-content: space-between;
                  gap: 0.8rem;
                  font-size: 0.88rem;
                  color: var(--text);
                }

                .code-toggle::-webkit-details-marker {
                  display: none;
                }

                .code-toggle::after {
                  content: 'Open';
                  color: var(--muted);
                  font-size: 0.78rem;
                  letter-spacing: 0.03em;
                  text-transform: uppercase;
                }

                .code-block[open] .code-toggle::after {
                  content: 'Close';
                }

                .highlight {
                  margin: 0;
                  border-top: 1px solid var(--line);
                  border-radius: 0 0 10px 10px;
                  overflow-x: auto;
                }

                .highlight pre {
                  margin: 0;
                  padding: 0.8rem;
                  line-height: 1.35;
                }

                @media (max-width: 960px) {
                  :root { --sidebar-width: min(82vw, 320px); }

                  body.has-index main.container,
                  body.has-index.index-collapsed main.container {
                    width: calc(100% - 1rem);
                    margin: 4rem 0.5rem 1rem 0.5rem;
                  }

                  .report-index {
                    top: 3.5rem;
                    left: 0.5rem;
                    bottom: 0.5rem;
                  }

                  body.has-index.index-collapsed .report-index {
                    transform: translateX(calc(-1 * (var(--sidebar-width) + 0.6rem)));
                  }
                }

                #{rouge_theme_css}
              </style>
            </head>
            <body>
              <main class="container">
        HTML
      end

      def render_index
        return '' if @index_entries.empty?

        index_items = @index_entries.map do |entry|
          label = escape(index_label(entry))
          "<li class=\"index-item\" style=\"--index-level: #{entry[:level]};\"><a class=\"index-link\" href=\"##{entry[:anchor_id]}\" title=\"#{label}\">#{label}</a></li>"
        end.join

        <<~HTML
          <button type="button" class="index-toggle" aria-expanded="false" aria-controls="report-index">Show index</button>
          <nav id="report-index" class="report-index" aria-label="Report index">
            <h2 class="index-title">Index</h2>
            <ul class="index-list">
              #{index_items}
            </ul>
          </nav>
          <script>
            (function() {
              var body = document.body;
              var nav = document.getElementById('report-index');
              var toggle = document.querySelector('.index-toggle');
              if (!body || !nav || !toggle) return;

              body.classList.add('has-index');

              var syncToggleLabel = function() {
                var isCollapsed = body.classList.contains('index-collapsed');
                toggle.setAttribute('aria-expanded', String(!isCollapsed));
                toggle.textContent = isCollapsed ? 'Show index' : 'Hide index';
              };

              toggle.addEventListener('click', function() {
                body.classList.toggle('index-collapsed');
                syncToggleLabel();
              });

              syncToggleLabel();
            })();
          </script>
        HTML
      end

      def index_label(entry)
        marker =
          case entry[:type]
          when :context then '+'
          else '-'
          end

        "#{marker} #{entry[:label]}"
      end

      def add_index_entry(type:, label:, level:, anchor_id:)
        @index_entries << {
          type:,
          label: normalize_text(label),
          level: [level, 0].max,
          anchor_id:
        }
      end

      def next_anchor_id(prefix)
        @anchor_counters[prefix] += 1
        "#{prefix}-#{@anchor_counters[prefix]}"
      end

      def render_labeled_value(label, value)
        if code_object?(value)
          @content << "<p class=\"line\"><strong>#{escape(label)}:</strong></p>"
          @content << render_code_block(value)
        else
          @content << "<p class=\"line\"><strong>#{escape(label)}:</strong> #{escape(serialize(value).to_s)}</p>"
        end
      end

      def render_matcher_value(label, value)
        if code_object?(value)
          @content << "<p class=\"line\"><strong>Matcher:</strong> #{escape(label)} (#{escape(value.language)})</p>"
          @content << render_code_block(value)
        else
          @content << "<p class=\"line\"><strong>Matcher:</strong> #{escape(label)} #{escape(serialize(value).to_s)}</p>"
        end
      end

      def render_value_block(label, value)
        @content << '<div class="subject-block">'
        if inline_value?(value)
          @content << "<p class=\"line\"><strong>#{escape(label)}:</strong> #{escape(serialize(value).to_s)}</p>"
        else
          @content << "<p class=\"line\"><strong>#{escape(label)}:</strong></p>"
          render_nested_subject_value(value, depth: 0)
        end
        @content << '</div>'
      end

      def render_nested_subject_value(value, depth:)
        case value
        when Hash
          if value.empty?
            @content << nested_value_line('{}', depth:)
            return
          end

          value.each do |key, nested_value|
            @content << nested_key_line("#{serialize(key)}:", depth:)
            render_nested_subject_value(nested_value, depth: depth + 1)
          end
        when Array
          if value.empty?
            @content << nested_value_line('[]', depth:)
            return
          end

          value.each_with_index do |entry, index|
            @content << nested_key_line("[#{index}]:", depth:)
            render_nested_subject_value(entry, depth: depth + 1)
          end
        else
          render_leaf_subject_value(value, depth:)
        end
      end

      def render_leaf_subject_value(value, depth:)
        if code_object?(value)
          @content << %(<div class="nested-block" style="--nest-depth: #{depth};">#{render_code_block(value)}</div>)
          return
        end

        if image_file?(value)
          image_path = file_path(value)
          @content << nested_value_line("Image file: #{image_path}", depth:)
          @content << %(<img src="#{image_data_uri(image_path)}" alt="subject image" class="subject-image nested-block" style="--nest-depth: #{depth};" />)
          return
        end

        if pdf_file?(value)
          pdf_path = file_path(value)
          @content << nested_value_line("PDF file: #{pdf_path}", depth:)
          @content << %(<embed src="#{pdf_data_uri(pdf_path)}" type="application/pdf" class="subject-pdf nested-block" style="--nest-depth: #{depth};" />)
          return
        end

        if pdf_reader?(value)
          @content << nested_value_line('PDF::Reader value', depth:)
          @content << %(<embed src="#{pdf_reader_data_uri(value)}" type="application/pdf" class="subject-pdf nested-block" style="--nest-depth: #{depth};" />)
          return
        end

        @content << nested_value_line(serialize(value).to_s, depth:)
      end

      def nested_key_line(key, depth:)
        %(<p class="line nested-key" style="--nest-depth: #{depth};"><strong>#{escape(key)}</strong></p>)
      end

      def nested_value_line(value, depth:)
        %(<p class="line nested-value" style="--nest-depth: #{depth};">#{escape(value)}</p>)
      end

      def inline_value?(value)
        !code_object?(value) &&
          !value.is_a?(Hash) &&
          !value.is_a?(Array) &&
          !image_file?(value) &&
          !pdf_file?(value) &&
          !pdf_reader?(value)
      end

      def render_code_block(code)
        source = normalize_text(code.source)
        language = normalize_text(code.language)
        highlighted = highlight_code(source, language)
        <<~HTML
          <details class="code-block">
            <summary class="code-toggle">
              <span class="code-language">#{escape(language)}</span>
            </summary>
            #{highlighted}
          </details>
        HTML
      end

      def highlight_code(source, language)
        lexer = rouge_lexer_for(source, language)
        @rouge_formatter.format(lexer.lex(source))
      end

      def rouge_lexer_for(source, language)
        Rouge::Lexer.find_fancy(language, source) || Rouge::Lexers::PlainText
      rescue StandardError
        Rouge::Lexers::PlainText
      end

      def rouge_theme_css
        Rouge::Themes::Github.render(scope: '.highlight')
      end

      def escape(message)
        CGI.escape_html(normalize_text(message))
      end

      def normalize_text(value)
        value.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
      end

      def image_file?(value)
        path = file_path(value)
        !path.nil? && path.match?(/\.(png|jpe?g)\z/i)
      end

      def image_data_uri(path)
        mime_type = path.downcase.end_with?('.png') ? 'image/png' : 'image/jpeg'
        encoded = Base64.strict_encode64(File.binread(path))
        "data:#{mime_type};base64,#{encoded}"
      end

      def pdf_file?(value)
        path = file_path(value)
        !path.nil? && path.match?(/\.pdf\z/i)
      end

      def pdf_data_uri(path)
        encoded = Base64.strict_encode64(File.binread(path))
        "data:application/pdf;base64,#{encoded}"
      end

      def pdf_reader?(value)
        defined?(PDF::Reader) && value.is_a?(PDF::Reader)
      end

      def pdf_reader_data_uri(reader)
        objects = reader.instance_variable_get(:@objects)
        io = objects&.instance_variable_get(:@io)
        pdf_content =
          if io.respond_to?(:string)
            io.string
          elsif io.respond_to?(:read)
            current_pos = io.pos if io.respond_to?(:pos)
            content = io.read
            io.seek(current_pos) if io.respond_to?(:seek) && !current_pos.nil?
            content
          end

        raise ArgumentError, 'Unable to extract PDF bytes from PDF::Reader subject.' unless pdf_content

        "data:application/pdf;base64,#{Base64.strict_encode64(pdf_content)}"
      end

      def file_path(value)
        return value.path if value.is_a?(File)
        return nil unless value.respond_to?(:path)

        path = value.path
        path.is_a?(String) && !path.empty? ? path : nil
      rescue StandardError
        nil
      end
    end
  end
end
