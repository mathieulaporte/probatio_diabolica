require 'stringio'

describe 'MCP server' do
  class FakeRunSpecsTool
    def call(_arguments)
      {
        ok: true,
        exit_code: 0,
        summary: { passed: 1, failed: 0, pending: 0 },
        artifacts: { base_out: nil, reports: [], annex_dir: nil },
        logs: { stdout: 'PASS: ok', stderr: '' }
      }
    end
  end

  let(:server) do
    PrD::Mcp::Server.new(input: StringIO.new, output: StringIO.new, run_specs_tool: FakeRunSpecsTool.new)
  end

  context 'when listing tools' do
    let(:response) { server.process_message({ 'id' => 1, 'method' => 'tools/list' }) }
    subject { response.dig(:result, :tools) }

    it 'lists run_specs tool' do
      expect(subject.length).to(eq(1))
      expect(subject.first[:name]).to(eq('run_specs'))
    end

    it 'declares jobs argument in tool schema' do
      jobs_schema = subject.first.dig(:inputSchema, :properties, :jobs)

      expect(jobs_schema[:type]).to(eq('integer'))
      expect(jobs_schema[:minimum]).to(eq(1))
    end
  end

  context 'when initializing MCP session' do
    let(:response) do
      server.process_message({
        'id' => 10,
        'method' => 'initialize',
        'params' => {
          'protocolVersion' => '2024-11-05',
          'capabilities' => {},
          'clientInfo' => { 'name' => 'spec-client', 'version' => '1.0.0' }
        }
      })
    end

    it 'returns initialize result without internal error' do
      expect(response[:error]).to(eq(nil))
      expect(response.dig(:result, :serverInfo, :name)).to(eq('probatio-diabolica-mcp'))
      expect(response.dig(:result, :serverInfo, :version)).to(eq(PrD::VERSION))
    end

    it 'still supports tools/list after initialize' do
      server.process_message({
        'id' => 10,
        'method' => 'initialize',
        'params' => {
          'protocolVersion' => '2024-11-05',
          'capabilities' => {},
          'clientInfo' => { 'name' => 'spec-client', 'version' => '1.0.0' }
        }
      })

      tools_response = server.process_message({ 'id' => 11, 'method' => 'tools/list' })
      tools = tools_response.dig(:result, :tools)

      expect(tools.length).to(eq(1))
      expect(tools.first[:name]).to(eq('run_specs'))
    end
  end

  context 'when calling run_specs' do
    subject do
      server.process_message({
        'id' => 2,
        'method' => 'tools/call',
        'params' => {
          'name' => 'run_specs',
          'arguments' => { 'path' => 'spec' }
        }
      })
    end
    
    it 'returns structured content' do
      expect(subject[:id]).to(eq(2))
      expect(subject.dig(:result, :structuredContent, :ok)).to(eq(true))
    end
  end

  context 'when calling an unknown tool' do
    subject do
      server.process_message({
        'id' => 3,
        'method' => 'tools/call',
        'params' => {
          'name' => 'unknown_tool',
          'arguments' => {}
        }
      })
    end

    it 'returns a tool error' do
      expect(subject.dig(:result, :isError)).to(eq(true))
    end
  end
end
