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

  it 'lists run_specs tool' do
    response = server.process_message({ 'id' => 1, 'method' => 'tools/list' })
    tools = response.dig(:result, :tools)

    expect(tools.length).to(eq(1))
    expect(tools.first[:name]).to(eq('run_specs'))
  end

  it 'calls run_specs and returns structured content' do
    response = server.process_message({
      'id' => 2,
      'method' => 'tools/call',
      'params' => {
        'name' => 'run_specs',
        'arguments' => { 'path' => 'spec' }
      }
    })

    expect(response[:id]).to(eq(2))
    expect(response.dig(:result, :structuredContent, :ok)).to(eq(true))
  end

  it 'returns tool errors for unknown tools' do
    response = server.process_message({
      'id' => 3,
      'method' => 'tools/call',
      'params' => {
        'name' => 'unknown_tool',
        'arguments' => {}
      }
    })

    expect(response.dig(:result, :isError)).to(eq(true))
  end
end
