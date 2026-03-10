require 'digest'
require 'fileutils'
require 'pdf-reader'

module PrD
  module Helpers
    module ChromeHelper
      def screen(at:, width: 1280, height: 800, warmup_time: 2)
        browser = prepare_browser(at:, warmup_time:)
        browser.set_viewport(width:, height:)
        yield browser if block_given?

        screenshot_id = Digest::SHA256.hexdigest("#{at}-#{width}-#{height}-#{warmup_time}")
        file_name = File.join(chrome_annex_dir, "screenshot-#{screenshot_id}.png")
        browser.screenshot(path: file_name, area: { x: 0, y: 0, width:, height: })
        File.open(file_name, 'rb')
      end

      def text(at:, css: 'body', warmup_time: 2)
        browser = prepare_browser(at:, warmup_time:)
        yield browser if block_given?

        text_node = browser.at_css(css)
        raise ArgumentError, "CSS selector not found: #{css}" unless text_node

        text_id = Digest::SHA256.hexdigest("#{at}-#{css}")
        file_name = File.join(chrome_annex_dir, "text-#{text_id}.txt")
        File.open(file_name, 'w') do |file|
          file.write(text_node.text.scan(/.{1,100}/m).join("\n"))
        end
        File.open(file_name, 'rb')
      end

      def network(at:, warmup_time: 2)
        browser = prepare_browser(at:, warmup_time:)
        yield browser if block_given?
        browser.network.traffic
      end

      def network_urls(at:, warmup_time: 2, &block)
        network(at:, warmup_time:, &block).map(&:url)
      end

      def pdf(at:, warmup_time: 2)
        browser = prepare_browser(at:, warmup_time:)
        yield browser if block_given?

        pdf_id = Digest::SHA256.hexdigest(at)
        file_name = File.join(chrome_annex_dir, "pdf-#{pdf_id}.pdf")
        browser.pdf(path: file_name)
        PDF::Reader.new(file_name)
      end

      def html(at:, warmup_time: 2)
        browser = prepare_browser(at:, warmup_time:)
        yield browser if block_given?
        browser.body
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
