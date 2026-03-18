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
        return ferrum_node_summary(value) if ferrum_node?(value)
        return value.path if value.is_a?(File)
        return value.map { |v| serialize(v) } if value.is_a?(Array)
        return value.transform_values { |v| serialize(v) } if value.is_a?(Hash)

        value
      end

      def code_object?(value)
        defined?(PrD::Code) && value.is_a?(PrD::Code)
      end

      def ferrum_node?(value)
        value.respond_to?(:class) && value.class.respond_to?(:name) && value.class.name == 'Ferrum::Node'
      rescue StandardError
        false
      end

      def ferrum_node_payload(node)
        payload = ferrum_node_payload_from_js(node) || {}
        payload[:tag] = payload[:tag].to_s.downcase.strip unless blank_text?(payload[:tag])
        payload[:id] = payload[:id].to_s.strip unless blank_text?(payload[:id])
        payload[:classes] = normalize_classes(payload[:classes])
        payload[:text] = normalize_preview_text(payload[:text], max_length: 160)
        payload[:html] = normalize_preview_text(payload[:html], max_length: 220)
        payload[:description] = normalize_preview_text(payload[:description], max_length: 160)
        payload
      rescue StandardError
        {}
      end

      def ferrum_node_summary(node)
        payload = ferrum_node_payload(node)
        selector = ferrum_node_selector(payload)
        summary = +'Ferrum::Node'
        summary << " <#{selector}>" unless selector.nil?

        if blank_text?(payload[:text]) && !blank_text?(payload[:description])
          summary << " #{payload[:description]}"
          return summary
        end

        summary << %( text="#{payload[:text]}") unless blank_text?(payload[:text])
        summary
      rescue StandardError
        'Ferrum::Node'
      end

      def ferrum_node_selector(payload)
        return nil unless payload.is_a?(Hash)

        selector = +''
        selector << payload[:tag].to_s unless blank_text?(payload[:tag])
        selector << "##{payload[:id]}" unless blank_text?(payload[:id])
        Array(payload[:classes]).each do |class_name|
          class_name_text = class_name.to_s.strip
          next if class_name_text.empty?

          selector << ".#{class_name_text}"
        end

        return nil if selector.empty?

        selector
      end

      def ferrum_node_payload_from_js(node)
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

      def safe_node_call(node, method_name)
        return nil unless node.respond_to?(method_name)

        node.public_send(method_name)
      rescue StandardError
        nil
      end

      def normalize_classes(value)
        Array(value)
          .flat_map { |entry| entry.to_s.split(/\s+/) }
          .map(&:strip)
          .reject(&:empty?)
          .uniq
      end

      def normalize_preview_text(value, max_length:)
        text = value.to_s.gsub(/\s+/, ' ').strip
        return nil if text.empty?
        return text if text.length <= max_length

        "#{text[0, max_length - 3]}..."
      end

      def blank_text?(value)
        value.nil? || value.to_s.strip.empty?
      end
    end
  end
end
