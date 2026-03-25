require 'digest'
require 'fileutils'
require 'pdf-reader'

module PrD
  module Helpers
    module ChromeHelper
      class BrowserSession
        SHADOW_QUERY_FUNCTION = <<~JS.freeze
          function(shadowSelectors, targetSelector, within) {
            let scope = within || document;

            for (const scopeSelector of shadowSelectors) {
              if (!scope || typeof scope.querySelector !== "function") return null;
              const node = scope.querySelector(scopeSelector);
              if (!node) return null;
              scope = node.shadowRoot || node;
            }

            if (!scope || typeof scope.querySelector !== "function") return null;
            return scope.querySelector(targetSelector);
          }
        JS

        def initialize(browser, poll_interval: 0.05)
          @browser = browser
          @poll_interval = poll_interval
        end

        attr_reader :browser

        def navigate(to:, warmup_time: 0)
          @browser.go_to(to)
          sleep(warmup_time.to_f) if warmup_time.to_f.positive?
          self
        end

        def wait(seconds)
          sleep(seconds.to_f) if seconds.to_f.positive?
          self
        end

        def wait_for(css: nil, xpath: nil, within: nil, shadow: nil, timeout: 2)
          find(css:, xpath:, within:, shadow:, wait: timeout)
        end

        def exists?(css: nil, xpath: nil, within: nil, shadow: nil, wait: 0)
          !find(css:, xpath:, within:, shadow:, wait:, raise_on_missing: false).nil?
        end

        def find(css: nil, xpath: nil, within: nil, shadow: nil, wait: 2, raise_on_missing: true)
          selector = normalize_selector(css:, xpath:)
          node = find_with_wait(selector:, within:, shadow:, wait:)
          return node if node
          return nil unless raise_on_missing

          raise ArgumentError, "Selector not found: #{selector[:label]}"
        end

        def click(css: nil, xpath: nil, within: nil, shadow: nil, wait: 2, mode: :left, keys: [], offset: {}, delay: 0)
          node = find(css:, xpath:, within:, shadow:, wait:)
          node.scroll_into_view
          node.click(mode:, keys:, offset:, delay:)
          node
        end

        def fill(css: nil, xpath: nil, within: nil, shadow: nil, with:, wait: 2, clear: true, blur: false, dispatch_events: true)
          node = find(css:, xpath:, within:, shadow:, wait:)
          node.focus
          node.evaluate("this.value = ''") if clear
          node.type(with.to_s)
          dispatch_input_events(node) if dispatch_events
          node.blur if blur
          node
        end

        def select_option(css:, within: nil, shadow: nil, value: nil, values: nil, by: :value, wait: 2)
          node = find(css:, within:, shadow:, wait:)
          option_values = Array(values || value).flatten.compact
          raise ArgumentError, 'select_option requires `value` or `values`.' if option_values.empty?

          node.select(*option_values, by:)
          node
        end

        def set_files(css:, within: nil, shadow: nil, path: nil, paths: nil, wait: 2, dispatch_events: true)
          node = find(css:, within:, shadow:, wait:)
          file_paths = normalize_file_paths(path:, paths:)
          node.select_file(file_paths)
          dispatch_input_events(node) if dispatch_events
          node
        end
        alias upload_files set_files

        def method_missing(method_name, *args, **kwargs, &block)
          return @browser.public_send(method_name, *args, **kwargs, &block) if @browser.respond_to?(method_name)

          super
        end

        def respond_to_missing?(method_name, include_private = false)
          @browser.respond_to?(method_name, include_private) || super
        end

        private

        def normalize_selector(css:, xpath:)
          css = normalize_optional_selector(css)
          xpath = normalize_optional_selector(xpath)

          if css.nil? && xpath.nil?
            raise ArgumentError, 'Provide a selector with `css:` or `xpath:`.'
          end

          if css && xpath
            raise ArgumentError, 'Use either `css:` or `xpath:`, not both.'
          end

          if xpath && !xpath.nil?
            { type: :xpath, value: xpath, label: "xpath=#{xpath}" }
          else
            { type: :css, value: css, label: "css=#{css}" }
          end
        end

        def normalize_optional_selector(value)
          return nil if value.nil?

          selector = value.to_s.strip
          return nil if selector.empty?

          selector
        end

        def find_with_wait(selector:, within:, shadow:, wait:)
          timeout = wait.to_f
          timeout = 0 if timeout.negative?
          deadline = monotonic_now + timeout

          loop do
            node = resolve_node(selector:, within:, shadow:)
            return node if node

            break if monotonic_now >= deadline

            sleep(@poll_interval)
          end

          nil
        end

        def resolve_node(selector:, within:, shadow:)
          case selector[:type]
          when :xpath
            raise ArgumentError, '`shadow:` can only be used with `css:` selectors.' if shadow && !Array(shadow).empty?

            within ? within.at_xpath(selector[:value]) : @browser.at_xpath(selector[:value])
          when :css
            if shadow && !Array(shadow).empty?
              @browser.evaluate_func(SHADOW_QUERY_FUNCTION, Array(shadow), selector[:value], within)
            elsif within
              within.at_css(selector[:value])
            else
              @browser.at_css(selector[:value])
            end
          end
        end

        def dispatch_input_events(node)
          node.evaluate("this.dispatchEvent(new Event('input', { bubbles: true }))")
          node.evaluate("this.dispatchEvent(new Event('change', { bubbles: true }))")
        end

        def normalize_file_paths(path:, paths:)
          raw_paths = Array(paths || path).flatten.compact.map { |value| value.to_s.strip }.reject(&:empty?)
          raise ArgumentError, 'set_files requires `path` or `paths`.' if raw_paths.empty?

          expanded_paths = raw_paths.map { |file_path| File.expand_path(file_path, Dir.pwd) }
          missing = expanded_paths.reject { |file_path| File.exist?(file_path) }
          raise ArgumentError, "File not found: #{missing.join(', ')}" unless missing.empty?

          expanded_paths
        end

        def monotonic_now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end

      def page(at:, warmup_time: 2)
        session = prepare_browser_session(at:, warmup_time:)
        yield session if block_given?
        session
      end

      def screen(at:, width: 1280, height: 800, warmup_time: 2)
        session = prepare_browser_session(at:, warmup_time:)
        browser = session.browser
        browser.set_viewport(width:, height:)
        yield session if block_given?

        screenshot_id = Digest::SHA256.hexdigest("#{at}-#{width}-#{height}-#{warmup_time}")
        file_name = File.join(chrome_annex_dir, "screenshot-#{screenshot_id}.png")
        browser.screenshot(path: file_name, area: { x: 0, y: 0, width:, height: })
        File.open(file_name, 'rb')
      end

      def text(at:, css: 'body', warmup_time: 2)
        session = prepare_browser_session(at:, warmup_time:)
        yield session if block_given?

        text_node = session.find(css:, wait: 0, raise_on_missing: false)
        raise ArgumentError, "CSS selector not found: #{css}" unless text_node

        PrD::Code.new(source: text_node.text, language: 'text')
      end

      def network(at:, warmup_time: 2)
        session = prepare_browser_session(at:, warmup_time:)
        yield session if block_given?
        session.browser.network.traffic
      end

      def network_urls(at:, warmup_time: 2, &block)
        network(at:, warmup_time:, &block).map(&:url)
      end

      # return the request when it is finished, or raise Timeout::Error if it doesn't finish within the timeout
      def wait_for_network_url_done(at:, url:, warmup_time: 2, timeout: 20)
        session = prepare_browser_session(at:, warmup_time:)
        yield session if block_given?
        deadline = Time.now + timeout.to_f
        loop do
          request = session.browser.network.traffic.find { |request| request.url == url && request.finished? }
          break request if request
          raise Timeout::Error, "Timeout waiting for network request: #{url}" if Time.now > deadline
          sleep(0.1)
        end
      end

      def pdf(at:, warmup_time: 2)
        session = prepare_browser_session(at:, warmup_time:)
        browser = session.browser
        yield session if block_given?

        pdf_id = Digest::SHA256.hexdigest(at)
        file_name = File.join(chrome_annex_dir, "pdf-#{pdf_id}.pdf")
        browser.pdf(path: file_name)
        PDF::Reader.new(file_name)
      end

      def html(at:, warmup_time: 2)
        session = prepare_browser_session(at:, warmup_time:)
        yield session if block_given?

        PrD::Code.new(source: session.browser.body, language: 'html')
      end

      def close_chrome_browser
        return unless @browser

        @browser.quit
      ensure
        @browser = nil
      end

      private

      def chrome_browser
        ensure_ferrum_loaded!
        @browser ||= Ferrum::Browser.new
      end

      def prepare_browser_session(at:, warmup_time:)
        browser = prepare_browser(at:, warmup_time:)
        BrowserSession.new(browser)
      end

      def prepare_browser(at:, warmup_time:)
        browser = chrome_browser
        browser.go_to(at)
        sleep(warmup_time) if warmup_time.to_f.positive?
        browser
      end

      def chrome_annex_dir
        base_dir = @output_dir || File.join(Dir.pwd, 'tmp')
        annex_dir = File.join(base_dir, 'annex')
        FileUtils.mkdir_p(annex_dir)
        annex_dir
      end

      def ensure_ferrum_loaded!
        return if defined?(::Ferrum::Browser)

        require 'ferrum'
      rescue LoadError => e
        raise LoadError, "Browser helpers require the 'ferrum' gem. Install it with `gem install ferrum` or add `gem 'ferrum'` to your Gemfile. (#{e.message})"
      end
    end
  end
end
