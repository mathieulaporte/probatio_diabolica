require 'tmpdir'
require 'tempfile'
require 'json'

def with_temp_spec_file(prefix, body)
  spec_file = Tempfile.new([prefix, '_spec.rb'])
  spec_file.write(body)
  spec_file.flush
  yield spec_file.path
ensure
  spec_file.close! if spec_file
end

describe 'MCP run_specs tool' do
  let(:tool) { PrD::Mcp::RunSpecsTool.new }

  context 'with a valid spec file' do
    let(:result) do
      with_temp_spec_file('mcp_run_specs_ok', <<~SPEC) do |path|
        describe 'MCP pass suite' do
          it 'passes' do
            expect(1).to(eq(1))
          end
        end
      SPEC
        tool.call({ 'path' => path })
      end
    end

    it 'returns a successful summary' do
      expect(result[:ok]).to(eq(true))
      expect(result[:exit_code]).to(eq(0))
      expect(result[:summary]).to(eq({ passed: 1, failed: 0, pending: 0 }))
      expect(result[:artifacts]).to(eq({ base_out: nil, reports: [], annex_dir: nil }))
      expect(result.dig(:logs, :stderr)).to(eq(''))
    end
  end

  it 'runs a directory and reports failures with exit code 1' do
    Dir.mktmpdir('mcp_run_specs_dir') do |tmp_dir|
      File.write(File.join(tmp_dir, 'a_spec.rb'), <<~SPEC)
        describe 'dir pass' do
          it 'passes' do
            expect(1).to(eq(1))
          end
        end
      SPEC

      File.write(File.join(tmp_dir, 'b_spec.rb'), <<~SPEC)
        describe 'dir fail' do
          it 'fails' do
            expect(1).to(eq(2))
          end
        end
      SPEC

      result = tool.call({ 'path' => tmp_dir })

      expect(result[:ok]).to(eq(true))
      expect(result[:exit_code]).to(eq(1))
      expect(result[:summary][:passed]).to(eq(1))
      expect(result[:summary][:failed]).to(eq(1))
    end
  end

  context 'with a missing path' do
    let(:error_message) do
      begin
        tool.call({ 'path' => './spec/path_that_does_not_exist.rb' })
        nil
      rescue StandardError => e
        e.message
      end
    end

    it 'raises an explicit error' do
      expect(error_message).to(eq('Path not found: ./spec/path_that_does_not_exist.rb'))
    end
  end

  context 'with an unsupported mode' do
    let(:error_message) do
      begin
        tool.call({ 'path' => 'spec', 'mode' => 'compact' })
        nil
      rescue StandardError => e
        e.message
      end
    end

    it 'raises an explicit error' do
      expect(error_message).to(eq('Unsupported mode: compact'))
    end
  end

  it 'generates artifacts for html and json formatters when out is set' do
    with_temp_spec_file('mcp_run_specs_artifacts', <<~SPEC) do |spec_path|
        describe 'artifact suite' do
          it 'passes' do
            expect(1).to(eq(1))
          end
        end
      SPEC

      Dir.mktmpdir('mcp_artifacts') do |tmp_dir|
        out_base = File.join(tmp_dir, 'report_bundle')
        result = tool.call({
          'path' => spec_path,
          'formatters' => %w[html json],
          'out' => out_base
        })

        expect(result[:ok]).to(eq(true))
        expect(result[:exit_code]).to(eq(0))
        expect(result[:artifacts][:base_out]).to(eq(out_base))

        reports = result[:artifacts][:reports]
        expect(reports.length).to(eq(2))

        html_report = reports.find { |report| report[:type] == 'html' }
        json_report = reports.find { |report| report[:type] == 'json' }

        expect(html_report[:exists]).to(eq(true))
        expect(json_report[:exists]).to(eq(true))
      end
    end
  end

  context 'when pdf is requested without out' do
    let(:error_message) do
      with_temp_spec_file('mcp_run_specs_pdf', <<~SPEC) do |path|
          describe 'pdf suite' do
            it 'passes' do
              expect(1).to(eq(1))
            end
          end
        SPEC

        begin
          tool.call({ 'path' => path, 'formatters' => ['pdf'] })
          nil
        rescue StandardError => e
          e.message
        end
      end
    end

    it 'raises an explicit error' do
      expect(error_message).to(eq('Using multiple formatters or pdf requires `out`.'))
    end
  end
end
