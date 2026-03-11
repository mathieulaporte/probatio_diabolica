require 'cgi'
require 'base64'

module PrD
  module Formatters
    class HtmlFormatter < Formatter
      def initialize(io: $stdout, serializers: {}, mode: :verbose)
        super(io: io, serializers: serializers, mode: mode)
        @io << <<~HTML
          <html>
            <head>
              <meta charset="utf-8" />
              <meta name="viewport" content="width=device-width, initial-scale=1" />
              <link rel="preconnect" href="https://fonts.googleapis.com">
              <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
              <link href="https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,600;9..144,700&family=Source+Sans+3:wght@400;500;600&display=swap" rel="stylesheet">
              <style>
                :root {
                  --bg: #f3f4f6;
                  --paper: #ffffff;
                  --ink: #1f2937;
                  --muted: #6b7280;
                  --line: #e5e7eb;
                  --accent: #0f766e;
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

                .context {
                  font-family: "Fraunces", Georgia, serif;
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
                  font-family: "Fraunces", Georgia, serif;
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
              </style>
            </head>
            <body>
              <main class="container">
        HTML
      end

      def context(message)
        return if synthetic?
        @io << "<h2 class=\"context\">#{escape(message)}</h2>"
      end

      def success_result(message)
        if synthetic?
          @io << "<div class='status success'>PASS</div>"
          return
        end
        @io << "<div class='status success'>✓ #{escape(message)}</div>"
      end

      def failure_result(message)
        if synthetic?
          @io << "<div class='status failure'>FAIL</div>"
          return
        end
        @io << "<div class='status failure'>✗ #{escape(message)}</div>"
      end

      def it(description = nil, &block)
        @current_test_title = description.to_s
        @io << '<article class="test-card">'
        @io << "<h3 class=\"test-title\">#{escape(description)}</h3>"
      end

      def end_it(description = nil, &block)
        @io << '</article>'
      end

      def justification(justification)
        return if synthetic?
        @io << "<p class=\"line\"><strong>Justification:</strong> #{escape(justification)}</p>"
      end

      def let(value)
      end

      def subject(subject)
        return if synthetic?
        @io << '<div class="subject-block">'
        @io << "<p class=\"line\"><strong>Subject:</strong> #{escape(serialize(subject).to_s)}</p>"
        if image_file?(subject)
          @io << "<img src=\"#{image_data_uri(subject.path)}\" alt=\"Subject image\" class=\"subject-image\" />"
        elsif pdf_file?(subject)
          @io << "<embed src=\"#{pdf_data_uri(subject.path)}\" type=\"application/pdf\" class=\"subject-pdf\" />"
        elsif pdf_reader?(subject)
          @io << "<embed src=\"#{pdf_reader_data_uri(subject)}\" type=\"application/pdf\" class=\"subject-pdf\" />"
        end
        @io << '</div>'
      end

      def pending(description = nil)
        if synthetic?
          @io << '<article class="test-card">'
          @io << "<h3 class=\"test-title\">#{escape(description || 'Pending test')}</h3>"
          @io << "<div class='status pending'>PENDING</div>"
          @io << '</article>'
          return
        end
        @io << "<div class='status pending'>⚠ #{escape(description || 'Pending test')}</div>"
        @io << '<p class="line muted">This test is pending and has not been executed.</p>'
      end

      def expect(expectation)
        return if synthetic?
        @io << "<p class=\"line\"><strong>Expect:</strong> #{escape(serialize(expectation).to_s)}</p>"
      end

      def to
        return if synthetic?
        @io << '<p class="line"><strong>To:</strong></p>'
      end

      def not_to
        return if synthetic?
        @io << '<p class="line"><strong>Not to:</strong></p>'
      end

      def matcher(matcher, sources: nil)
        return if synthetic?
        case matcher
        when Matchers::EqMatcher
          @io << "<p class=\"line\"><strong>Matcher:</strong> Be equal to #{escape(serialize(matcher.expected).to_s)}</p>"
        when Matchers::BeMatcher
          @io << "<p class=\"line\"><strong>Matcher:</strong> Be the same object as #{escape(serialize(matcher.expected).to_s)}</p>"
        when Matchers::IncludesMatcher
          @io << "<p class=\"line\"><strong>Matcher:</strong> Include #{escape(serialize(matcher.expected).to_s)}</p>"
        when Matchers::HaveMatcher
          @io << "<p class=\"line\"><strong>Matcher:</strong> Have #{escape(serialize(matcher.expected).to_s)}</p>"
        when Matchers::LlmMatcher
          @io << "<p class=\"line\"><strong>Matcher:</strong> Satisfy condition #{escape(serialize(matcher.expected).to_s)}</p>"
        when Matchers::AllMatcher
          if sources
            code_line = matcher.expected.source_location.last.to_i
            code = sources.lines[code_line - 1]
            @io << "<p class=\"line\"><strong>Matcher:</strong> All match condition #{escape(code.strip)}</p>"
          else
            @io << '<p class="line"><strong>Matcher:</strong> All match the given condition</p>'
          end
        else
          @io << "<p class=\"line\"><strong>Matcher:</strong> #{escape(matcher.class.to_s)}</p>"
        end
      end

      def result(passed_count, failed_count)
        summary_class = failed_count > 0 ? 'failure' : 'success'
        @io << "<p class='result #{summary_class}'><strong>#{passed_count} passed, #{failed_count} failed</strong></p>"
      end

      def flush
        @io << '</main></body></html>'
        super
      end

      private

      def escape(message)
        CGI.escape_html(message.to_s)
      end

      def image_file?(value)
        value.is_a?(File) && value.path.match?(/\.(png|jpe?g)\z/i)
      end

      def image_data_uri(path)
        mime_type = path.downcase.end_with?('.png') ? 'image/png' : 'image/jpeg'
        encoded = Base64.strict_encode64(File.binread(path))
        "data:#{mime_type};base64,#{encoded}"
      end

      def pdf_file?(value)
        value.is_a?(File) && value.path.match?(/\.pdf\z/i)
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
    end
  end
end
