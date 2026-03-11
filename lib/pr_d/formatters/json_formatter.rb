require 'json'
require 'base64'

module PrD
  module Formatters
    class JsonFormatter < Formatter
      def initialize(io: $stdout, serializers: {}, mode: :verbose)
        super(io: io, serializers: serializers, mode: mode)
        @events = []
        @summary = { passed: 0, failed: 0 }
      end

      def title(message)
        return if synthetic?
        add_event(type: 'title', message: message)
      end

      def context(message)
        return if synthetic?
        add_event(type: 'context', message: message)
      end

      def success_result(message)
        if synthetic?
          add_event(type: 'test_result', title: @current_test_title, status: 'PASS')
          return
        end
        add_event(type: 'success_result', message: message)
      end

      def failure_result(message)
        if synthetic?
          add_event(type: 'test_result', title: @current_test_title, status: 'FAIL')
          return
        end
        add_event(type: 'failure_result', message: message)
      end

      def it(description = nil, &block)
        @current_test_title = description.to_s
        return if synthetic?
        add_event(type: 'it', description: description)
      end

      def end_it(description = nil, &block)
        return if synthetic?
        add_event(type: 'end_it', description: description)
      end

      def justification(justification)
        return if synthetic?
        add_event(type: 'justification', message: justification)
      end

      def pending(description = nil)
        if synthetic?
          add_event(type: 'test_result', title: description || 'Pending test', status: 'PENDING')
          return
        end
        add_event(type: 'pending', description: description)
      end

      def expect(expectation)
        return if synthetic?
        add_event(type: 'expect', value: serialize(expectation))
      end

      def to
        return if synthetic?
        add_event(type: 'to')
      end

      def not_to
        return if synthetic?
        add_event(type: 'not_to')
      end

      def matcher(matcher, sources: nil)
        return if synthetic?
        add_event(type: 'matcher', matcher: matcher.class.to_s, expected: serialize(matcher.expected))
      end

      def output(message, color = nil, figure: nil, indent: 0)
        return if synthetic?
        add_event(type: 'output', message: serialize(message), color: color, figure: figure, indent: indent)
      end

      def subject(subject)
        return if synthetic?
        add_event(type: 'subject', value: serialize(subject))
      end

      def result(passed_count, failed_count)
        @summary = { passed: passed_count, failed: failed_count }
        add_event(type: 'result', passed: passed_count, failed: failed_count)
      end

      def flush
        payload = { format: 'prd-json-v1', events: @events, summary: @summary }
        @io.puts JSON.pretty_generate(payload)
        super
      end

      private

      def add_event(type:, **payload)
        @events << payload.merge(type:, level: @level)
      end

      def serialize(value)
        serializer = @serializers[value.class]
        return serializer.call(value) if serializer

        if value.is_a?(File)
          return serialize_file(value)
        end

        if defined?(PDF::Reader) && value.is_a?(PDF::Reader)
          return serialize_pdf_reader(value)
        end

        if value.is_a?(Array)
          return value.map { |v| serialize(v) }
        end

        if value.is_a?(Hash)
          return value.transform_values { |v| serialize(v) }
        end

        value
      end

      def serialize_file(file)
        file.rewind if file.respond_to?(:rewind)
        content = file.read
        file.rewind if file.respond_to?(:rewind)

        {
          type: 'file',
          path: file.path,
          mime_type: mime_type_for_path(file.path),
          encoding: 'base64',
          bytes: Base64.strict_encode64(content || '')
        }
      end

      def serialize_pdf_reader(reader)
        pdf_content = pdf_reader_bytes(reader)
        {
          type: 'pdf_reader',
          mime_type: 'application/pdf',
          encoding: 'base64',
          bytes: Base64.strict_encode64(pdf_content || '')
        }
      end

      def pdf_reader_bytes(reader)
        objects = reader.instance_variable_get(:@objects)
        io = objects&.instance_variable_get(:@io)
        return io.string if io.respond_to?(:string)

        return nil unless io.respond_to?(:read)

        current_pos = io.pos if io.respond_to?(:pos)
        content = io.read
        io.seek(current_pos) if io.respond_to?(:seek) && !current_pos.nil?
        content
      end

      def mime_type_for_path(path)
        return 'application/octet-stream' if path.nil?

        case File.extname(path).downcase
        when '.png'
          'image/png'
        when '.jpg', '.jpeg'
          'image/jpeg'
        when '.pdf'
          'application/pdf'
        when '.txt'
          'text/plain'
        when '.html', '.htm'
          'text/html'
        when '.json'
          'application/json'
        when '.csv'
          'text/csv'
        else
          'application/octet-stream'
        end
      end
    end
  end
end
