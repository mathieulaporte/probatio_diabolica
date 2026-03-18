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
