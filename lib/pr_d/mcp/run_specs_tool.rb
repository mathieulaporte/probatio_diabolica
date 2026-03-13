require 'json'
require 'open3'

module PrD
  module Mcp
    class RunSpecsTool
      SUPPORTED_FORMATTERS = %w[simple html json pdf].freeze
      SUPPORTED_MODES = %w[verbose synthetic].freeze
      FORMATTER_EXTENSIONS = {
        'simple' => '.txt',
        'html' => '.html',
        'json' => '.json',
        'pdf' => '.pdf'
      }.freeze
      DEFAULT_REPORT_BASENAME = 'report'.freeze

      def initialize(command_runner: Open3, pwd: Dir.pwd)
        @command_runner = command_runner
        @pwd = pwd
      end

      def call(arguments)
        args = normalize_and_validate_arguments(arguments)
        command = build_command(args)
        stdout, stderr, status = @command_runner.capture3(*command, chdir: @pwd)

        base_out = args[:out] ? output_base_path(args[:out]) : nil
        parsed_json = parse_json_summary(args:, stdout:, base_out:)

        {
          ok: true,
          exit_code: status.exitstatus,
          summary: build_summary(args:, stdout:, parsed_json:),
          artifacts: build_artifacts(args:, base_out:),
          logs: {
            stdout: stdout,
            stderr: stderr
          }
        }
      rescue StandardError => e
        raise e if e.is_a?(ArgumentError)

        {
          ok: false,
          exit_code: nil,
          summary: { passed: nil, failed: nil, pending: nil },
          artifacts: { base_out: nil, reports: [], annex_dir: nil },
          logs: { stdout: '', stderr: "#{e.class}: #{e.message}" }
        }
      end

      private

      def normalize_and_validate_arguments(raw_args)
        raise ArgumentError, 'run_specs requires an arguments object.' unless raw_args.is_a?(Hash)

        path = raw_args['path'] || raw_args[:path]
        raise ArgumentError, 'run_specs requires `path` (string).' unless path.is_a?(String) && !path.strip.empty?

        absolute_path = File.expand_path(path, @pwd)
        raise ArgumentError, "Path not found: #{path}" unless File.exist?(absolute_path)

        formatters = normalize_formatters(raw_args['formatters'] || raw_args[:formatters])
        mode = normalize_mode(raw_args['mode'] || raw_args[:mode])
        out = normalize_optional_string(raw_args['out'] || raw_args[:out])
        config = normalize_optional_string(raw_args['config'] || raw_args[:config])

        if (formatters.length > 1 || formatters.include?('pdf')) && out.nil?
          raise ArgumentError, 'Using multiple formatters or pdf requires `out`.'
        end

        {
          path: absolute_path,
          formatters: formatters,
          mode: mode,
          out: out,
          config: config
        }
      end

      def normalize_optional_string(value)
        return nil if value.nil?
        return value if value.is_a?(String) && !value.strip.empty?

        raise ArgumentError, 'Optional arguments (`config`, `out`) must be non-empty strings when provided.'
      end

      def normalize_formatters(value)
        return ['simple'] if value.nil?

        unless value.is_a?(Array) && !value.empty?
          raise ArgumentError, '`formatters` must be a non-empty array when provided.'
        end

        formatters = value.map do |formatter|
          formatter_string = formatter.to_s.strip
          raise ArgumentError, '`formatters` cannot contain empty values.' if formatter_string.empty?

          formatter_string
        end

        unknown_formatter = formatters.find { |formatter| !SUPPORTED_FORMATTERS.include?(formatter) }
        raise ArgumentError, "Unsupported formatter: #{unknown_formatter}" if unknown_formatter

        formatters.uniq
      end

      def normalize_mode(value)
        return 'synthetic' if value.nil?

        mode = value.to_s
        raise ArgumentError, "Unsupported mode: #{mode}" unless SUPPORTED_MODES.include?(mode)

        mode
      end

      def build_command(args)
        bin_path = File.expand_path('../../../bin/prd', __dir__)
        command = ['bundle', 'exec', 'ruby', bin_path, args[:path]]
        command << '--mode' << args[:mode]

        args[:formatters].each do |formatter|
          command << '-t' << formatter
        end

        if args[:config]
          command << '-c' << File.expand_path(args[:config], @pwd)
        end

        if args[:out]
          command << '-o' << File.expand_path(args[:out], @pwd)
        end

        command
      end

      def build_summary(args:, stdout:, parsed_json:)
        parsed = parsed_json || parse_simple_summary(stdout)
        return { passed: nil, failed: nil, pending: nil } unless parsed

        pending_count = parsed[:pending]
        if pending_count.nil? && args[:mode] == 'synthetic' && args[:formatters].include?('simple')
          pending_count = pending_count_from_simple_output(stdout)
        end

        {
          passed: parsed[:passed],
          failed: parsed[:failed],
          pending: pending_count
        }
      end

      def parse_json_summary(args:, stdout:, base_out:)
        return nil unless args[:formatters].include?('json')

        json_payload = nil
        if base_out
          json_path = "#{base_out}#{FORMATTER_EXTENSIONS['json']}"
          json_payload = File.read(json_path) if File.exist?(json_path)
        elsif args[:formatters] == ['json']
          json_payload = stdout
        end

        return nil unless json_payload

        parsed = JSON.parse(json_payload)
        summary = parsed['summary'] || {}

        pending = nil
        events = parsed['events']
        if events.is_a?(Array)
          pending = events.count do |event|
            (event['type'] == 'test_result' && event['status'] == 'PENDING') || event['type'] == 'pending'
          end
        end

        {
          passed: summary['passed'],
          failed: summary['failed'],
          pending: pending
        }
      rescue JSON::ParserError
        nil
      end

      def parse_simple_summary(stdout)
        plain_output = strip_ansi(stdout)
        matches = plain_output.scan(/(\d+)\s+passed,\s+(\d+)\s+failed/)
        return nil if matches.empty?
        match = matches.last

        {
          passed: match[0].to_i,
          failed: match[1].to_i,
          pending: nil
        }
      end

      def pending_count_from_simple_output(stdout)
        strip_ansi(stdout).scan(/^PENDING:\s+/).count
      end

      def strip_ansi(text)
        text.gsub(/\e\[[0-9;]*m/, '')
      end

      def build_artifacts(args:, base_out:)
        reports = []
        if base_out
          args[:formatters].each do |formatter|
            report_path = "#{base_out}#{FORMATTER_EXTENSIONS.fetch(formatter)}"
            reports << {
              type: formatter,
              path: report_path,
              exists: File.exist?(report_path)
            }
          end
        end

        annex_dir = if base_out
          candidate = File.join(File.dirname(base_out), 'annex')
          candidate if Dir.exist?(candidate)
        end

        {
          base_out: base_out,
          reports: reports,
          annex_dir: annex_dir
        }
      end

      def output_base_path(out_path)
        resolved = File.expand_path(out_path, @pwd)
        if directory_like_path?(resolved)
          File.join(resolved, DEFAULT_REPORT_BASENAME)
        else
          ext = File.extname(resolved).downcase
          known_extensions = FORMATTER_EXTENSIONS.values
          known_extensions.include?(ext) ? resolved[...-ext.length] : resolved
        end
      end

      def directory_like_path?(path)
        path.end_with?(File::SEPARATOR) || Dir.exist?(path)
      end
    end
  end
end
