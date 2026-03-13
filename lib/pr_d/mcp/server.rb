require 'json'

module PrD
  module Mcp
    class Server
      JSONRPC_VERSION = '2.0'.freeze
      MCP_PROTOCOL_VERSION = '2024-11-05'.freeze
      RUN_SPECS_TOOL_NAME = 'run_specs'.freeze

      def initialize(input: $stdin, output: $stdout, run_specs_tool: RunSpecsTool.new)
        @input = input
        @output = output
        @run_specs_tool = run_specs_tool
      end

      def run
        while (message = read_message)
          response = process_message(message)
          write_message(response) if response
        end
      end

      def process_message(message)
        id = message['id']
        method = message['method']
        params = message['params'] || {}

        case method
        when 'initialize'
          success_response(id, initialize_result)
        when 'notifications/initialized'
          nil
        when 'tools/list'
          success_response(id, tools_list_result)
        when 'tools/call'
          success_response(id, handle_tool_call(params))
        else
          return nil unless id

          error_response(id, -32601, "Method not found: #{method}")
        end
      rescue StandardError => e
        return nil unless id

        error_response(id, -32603, "Internal error: #{e.message}")
      end

      private

      def initialize_result
        {
          protocolVersion: MCP_PROTOCOL_VERSION,
          capabilities: {
            tools: {}
          },
          serverInfo: {
            name: 'probatio-diabolica-mcp',
            version: PrD::VERSION
          }
        }
      end

      def tools_list_result
        {
          tools: [run_specs_definition]
        }
      end

      def run_specs_definition
        {
          name: RUN_SPECS_TOOL_NAME,
          description: 'Run probatio_diabolica specs from a file or directory path.',
          inputSchema: {
            type: 'object',
            properties: {
              path: { type: 'string', description: 'File or directory path containing spec(s).' },
              config: { type: 'string', description: 'Optional config file, equivalent to `-c`.' },
              out: { type: 'string', description: 'Optional output base path, equivalent to `-o`.' },
              formatters: {
                type: 'array',
                description: 'Optional formatter list.',
                items: {
                  type: 'string',
                  enum: RunSpecsTool::SUPPORTED_FORMATTERS
                }
              },
              mode: {
                type: 'string',
                enum: RunSpecsTool::SUPPORTED_MODES,
                description: 'Optional output mode.'
              }
            },
            required: ['path']
          }
        }
      end

      def handle_tool_call(params)
        tool_name = params['name']
        arguments = params['arguments'] || {}

        return tool_error("Unknown tool: #{tool_name}") unless tool_name == RUN_SPECS_TOOL_NAME

        result = @run_specs_tool.call(arguments)

        unless result[:ok]
          return tool_error(result.dig(:logs, :stderr) || 'run_specs failed unexpectedly.')
        end

        tool_success(result)
      rescue ArgumentError => e
        tool_error(e.message)
      end

      def tool_success(payload)
        {
          content: [{ type: 'text', text: JSON.pretty_generate(payload) }],
          structuredContent: payload
        }
      end

      def tool_error(message)
        {
          content: [{ type: 'text', text: message }],
          isError: true
        }
      end

      def success_response(id, result)
        {
          jsonrpc: JSONRPC_VERSION,
          id: id,
          result: result
        }
      end

      def error_response(id, code, message)
        {
          jsonrpc: JSONRPC_VERSION,
          id: id,
          error: {
            code: code,
            message: message
          }
        }
      end

      def read_message
        headers = {}

        while (line = @input.gets)
          line = line.strip
          break if line.empty?

          key, value = line.split(':', 2)
          next unless key && value

          headers[key.downcase] = value.strip
        end

        return nil if headers.empty?

        content_length = Integer(headers.fetch('content-length'))
        raw = @input.read(content_length)
        JSON.parse(raw)
      rescue EOFError
        nil
      end

      def write_message(message)
        payload = JSON.dump(message)
        @output.write("Content-Length: #{payload.bytesize}\r\n\r\n")
        @output.write(payload)
        @output.flush
      end
    end
  end
end
