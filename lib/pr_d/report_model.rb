require 'stringio'
require 'tempfile'

module PrD
  class ReportModel
    FerrumNodeSnapshot = Struct.new(:payload, :summary, keyword_init: true)

    attr_reader :events
    attr_accessor :summary

    def initialize
      @events = []
      @summary = { passed: 0, failed: 0 }
    end

    def add_event(name:, args:, kwargs:)
      @events << { name:, args:, kwargs: }
    end

    def snapshot(value)
      return value if value.nil?
      return value if immutable_scalar?(value)

      if code_object?(value)
        return PrD::Code.new(source: value.source.to_s.dup, language: value.language.to_s.dup)
      end

      if ferrum_node?(value)
        return FerrumNodeSnapshot.new(
          payload: ferrum_node_payload_snapshot(value),
          summary: ferrum_node_summary_snapshot(value)
        )
      end

      if file_like?(value)
        return snapshot_file(value)
      end

      if pdf_reader?(value)
        return snapshot_pdf_reader(value)
      end

      if value.is_a?(Array)
        return value.map { |entry| snapshot(entry) }
      end

      if value.is_a?(Hash)
        return value.each_with_object({}) { |(key, entry), acc| acc[snapshot(key)] = snapshot(entry) }
      end

      begin
        value.dup
      rescue StandardError
        value
      end
    end

    private

    def immutable_scalar?(value)
      value.is_a?(Numeric) || value.is_a?(Symbol) || value.equal?(true) || value.equal?(false)
    end

    def code_object?(value)
      defined?(PrD::Code) && value.is_a?(PrD::Code)
    end

    def ferrum_node?(value)
      value.respond_to?(:class) && value.class.respond_to?(:name) && value.class.name == 'Ferrum::Node'
    rescue StandardError
      false
    end

    def ferrum_node_payload_snapshot(node)
      return nil unless node.respond_to?(:evaluate)

      raw_payload = node.evaluate(<<~JS)
        (() => {
          const element = this;
          if (!element) return null;

          const rawClassName = element.className;
          const className =
            typeof rawClassName === "string" ? rawClassName :
            (rawClassName && typeof rawClassName.baseVal === "string" ? rawClassName.baseVal : "");

          const classes = className
            .split(/\\s+/)
            .map((token) => token.trim())
            .filter((token) => token.length > 0);

          const textValue = (element.innerText || element.textContent || "").replace(/\\s+/g, " ").trim();
          const htmlValue = element.outerHTML || "";

          return {
            tag: element.tagName ? element.tagName.toLowerCase() : null,
            id: element.id || null,
            classes,
            text: textValue.length > 160 ? `${textValue.slice(0, 157)}...` : textValue,
            html: htmlValue.length > 220 ? `${htmlValue.slice(0, 217)}...` : htmlValue
          };
        })()
      JS
      return nil unless raw_payload.is_a?(Hash)

      {
        tag: raw_payload['tag'] || raw_payload[:tag],
        id: raw_payload['id'] || raw_payload[:id],
        classes: raw_payload['classes'] || raw_payload[:classes],
        text: raw_payload['text'] || raw_payload[:text],
        html: raw_payload['html'] || raw_payload[:html]
      }
    rescue StandardError
      {
        tag: safe_node_call(node, :tag_name),
        text: safe_node_call(node, :text),
        description: safe_node_call(node, :description)
      }
    end

    def ferrum_node_summary_snapshot(node)
      return nil unless node.respond_to?(:evaluate)

      ferrum_node_payload_snapshot(node)
    rescue StandardError
      nil
    end

    def safe_node_call(node, method_name)
      return nil unless node.respond_to?(method_name)

      node.public_send(method_name)
    rescue StandardError
      nil
    end

    def file_like?(value)
      value.is_a?(File)
    end

    def snapshot_file(file)
      file.rewind if file.respond_to?(:rewind)
      bytes = file.read
      file.rewind if file.respond_to?(:rewind)
      ext = File.extname(file.path.to_s)
      temp = Tempfile.new(['prd_snapshot_', ext])
      temp.binmode
      temp.write(bytes || ''.b)
      temp.flush
      temp.rewind
      temp
    rescue StandardError
      file
    end

    def pdf_reader?(value)
      defined?(PDF::Reader) && value.is_a?(PDF::Reader)
    end

    def snapshot_pdf_reader(reader)
      return reader unless defined?(PDF::Reader)

      objects = reader.instance_variable_get(:@objects)
      io = objects&.instance_variable_get(:@io)
      bytes =
        if io.respond_to?(:string)
          io.string
        elsif io.respond_to?(:read)
          current_pos = io.pos if io.respond_to?(:pos)
          content = io.read
          io.seek(current_pos) if io.respond_to?(:seek) && !current_pos.nil?
          content
        end
      return reader if bytes.nil?

      PDF::Reader.new(StringIO.new(bytes))
    rescue StandardError
      reader
    end
  end
end
