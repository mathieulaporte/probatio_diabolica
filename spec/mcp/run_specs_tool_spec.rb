require 'tmpdir'
require 'tempfile'
require 'json'


describe 'MCP run_specs tool' do
  let(:tool) { PrD::Mcp::RunSpecsTool.new }

  it 'runs a valid spec file and returns a successful summary' do
    spec_file = Tempfile.new(['mcp_run_specs_ok', '_spec.rb'])
    begin
      spec_file.write(<<~SPEC)
        describe 'MCP pass suite' do
          it 'passes' do
            expect(1).to(eq(1))
          end
        end
      SPEC
      spec_file.flush

      result = tool.call({ 'path' => spec_file.path })

      expect(result[:ok]).to(eq(true))
      expect(result[:exit_code]).to(eq(0))
      expect(result[:summary]).to(eq({ passed: 1, failed: 0, pending: 0 }))
      expect(result[:artifacts]).to(eq({ base_out: nil, reports: [], annex_dir: nil }))
      expect(result.dig(:logs, :stderr)).to(eq(''))
    ensure
      spec_file.close!
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

  it 'raises explicit errors for invalid inputs' do
    error_message = begin
      tool.call({ 'path' => './spec/path_that_does_not_exist.rb' })
      nil
    rescue StandardError => e
      e.message
    end

    expect(error_message).to(eq('Path not found: ./spec/path_that_does_not_exist.rb'))

    mode_error = begin
      tool.call({ 'path' => 'spec', 'mode' => 'compact' })
      nil
    rescue StandardError => e
      e.message
    end

    expect(mode_error).to(eq('Unsupported mode: compact'))
  end

  it 'generates artifacts for html and json formatters when out is set' do
    spec_file = Tempfile.new(['mcp_run_specs_artifacts', '_spec.rb'])
    begin
      spec_file.write(<<~SPEC)
        describe 'artifact suite' do
          it 'passes' do
            expect(1).to(eq(1))
          end
        end
      SPEC
      spec_file.flush

      Dir.mktmpdir('mcp_artifacts') do |tmp_dir|
        out_base = File.join(tmp_dir, 'report_bundle')
        result = tool.call({
          'path' => spec_file.path,
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
    ensure
      spec_file.close!
    end
  end

  it 'raises an explicit error when pdf is requested without out' do
    spec_file = Tempfile.new(['mcp_run_specs_pdf', '_spec.rb'])
    begin
      spec_file.write(<<~SPEC)
        describe 'pdf suite' do
          it 'passes' do
            expect(1).to(eq(1))
          end
        end
      SPEC
      spec_file.flush

      error_message = begin
        tool.call({ 'path' => spec_file.path, 'formatters' => ['pdf'] })
        nil
      rescue StandardError => e
        e.message
      end

      expect(error_message).to(eq('Using multiple formatters or pdf requires `out`.'))
    ensure
      spec_file.close!
    end
  end
end
