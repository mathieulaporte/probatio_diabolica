require 'stringio'
require 'open3'
require 'json'
require 'tempfile'
require 'tmpdir'
require 'shellwords'

def capture_stderr
  previous_stderr = $stderr
  buffer = StringIO.new
  $stderr = buffer
  yield
ensure
  $stderr = previous_stderr
end

describe 'PrD self-hosted reliability' do
  let(:simple_report) do
    io = StringIO.new
    formatter = PrD::Formatters::SimpleFormatter.new(io:, serializers: {})

    PrD::Runtime.new(formatter:, output_dir: nil, config_file: nil).run([
      <<~SPEC
        describe 'Inner suite' do
          it 'passes eq' do
            expect(1).to(eq(1))
          end

          it 'fails eq' do
            expect(1).to(eq(2))
          end

          context 'subject behavior' do
            subject { 'hello world' }

            it 'uses subject with expect.to' do
              expect.to(includes('hello'))
            end
          end

          context 'negative expectation' do
            it 'supports not_to' do
              expect('abc').not_to(includes('z'))
            end
          end

          pending 'later'
        end
      SPEC
    ])

    io.rewind
    io.read
  end

  it 'reports pass/fail counts' do
    expect(simple_report).to(includes('3 passed, 1 failed'))
  end

  it 'prints failures in red' do
    expect(simple_report).to(includes("\e[31m✗ Test failed"))
  end

  it 'supports expect.to with subject' do
    expect(simple_report).to(includes('Uses subject with expect.to'))
  end

  it 'raises when satisfy is used without a model' do
    error_message = begin
      expect('text').to(satisfy('is true'))
      nil
    rescue StandardError => e
      e.message
    end

    expect(error_message).to(eq('LLM matcher requires a model. Set model: on context/it before using satisfy().'))
  end

  it 'returns a clear error when running with no tests' do
    io = StringIO.new
    runtime = PrD::Runtime.new(formatter: PrD::Formatters::SimpleFormatter.new(io:, serializers: {}), output_dir: nil)

    capture_stderr { runtime.run([]) }
    io.rewind
    output = io.read
    expect(output).to(includes('No tests found. Provide at least one spec content to run.'))
  end

  it 'fails fast on unknown formatter type in CLI' do
    _stdout, stderr, status = Open3.capture3('bundle exec ruby bin/prd spec/self_hosted_spec.rb -t unknown')

    expect(status.success?).to(be(false))
    expect(stderr).to(includes('Unsupported formatter type: unknown. Supported: simple, html, json, pdf'))
  end

  it 'fails fast on unknown output mode in CLI' do
    _stdout, stderr, status = Open3.capture3('bundle exec ruby bin/prd spec/self_hosted_spec.rb --mode compact')

    expect(status.success?).to(be(false))
    expect(stderr).to(includes('Unsupported mode: compact. Supported: verbose, synthetic'))
  end

  it 'fails fast on missing CLI path' do
    _stdout, stderr, status = Open3.capture3('bundle exec ruby bin/prd ./spec/does_not_exist_spec.rb')

    expect(status.success?).to(be(false))
    expect(stderr).to(includes('Path not found: ./spec/does_not_exist_spec.rb'))
  end

  it 'supports synthetic mode from CLI with compact output' do
    spec_file = Tempfile.new(['prd_cli_synthetic', '_spec.rb'])
    begin
      spec_file.write(<<~SPEC)
        describe 'CLI synthetic suite' do
          it 'passes' do
            expect(1).to(eq(1))
          end

          it 'fails' do
            expect(1).to(eq(2))
          end

          pending 'later'
        end
      SPEC
      spec_file.flush

      stdout, stderr, status = Open3.capture3("bundle exec ruby bin/prd #{spec_file.path} --mode synthetic")

      expect(status.success?).to(be(false))
      expect(stderr).to(eq(''))
      expect(stdout).to(includes('PASS: passes'))
      expect(stdout).to(includes('FAIL: fails'))
      expect(stdout).to(includes('PENDING: later'))
      expect(stdout).to(includes('1 passed, 1 failed'))
      expect(stdout).not_to(includes('Expect:'))
      expect(stdout).not_to(includes('Justification:'))
    ensure
      spec_file.close!
    end
  end

  it 'keeps verbose mode behavior from CLI' do
    spec_file = Tempfile.new(['prd_cli_verbose', '_spec.rb'])
    begin
      spec_file.write(<<~SPEC)
        describe 'CLI verbose suite' do
          it 'works' do
            expect(1).to(eq(1))
          end
        end
      SPEC
      spec_file.flush

      stdout, stderr, status = Open3.capture3("bundle exec ruby bin/prd #{spec_file.path} --mode verbose")

      expect(status.success?).to(be(true))
      expect(stderr).to(eq(''))
      expect(stdout).to(includes('Expect:'))
      expect(stdout).to(includes('Test passed successfully'))
    ensure
      spec_file.close!
    end
  end

  it 'generates multiple report formats from CLI with a shared output base path' do
    spec_file = Tempfile.new(['prd_cli_multi', '_spec.rb'])
    begin
      spec_file.write(<<~SPEC)
        describe 'CLI multi formatter suite' do
          context 'index coverage' do
            it 'works' do
              expect(1).to(eq(1))
            end

            pending 'later'
          end
        end
      SPEC
      spec_file.flush

      Dir.mktmpdir('prd_multi_output') do |tmp_dir|
        output_base = File.join(tmp_dir, 'my_report')
        command = [
          'bundle exec ruby bin/prd',
          Shellwords.escape(spec_file.path),
          '-t html,json',
          '-t pdf',
          '--out',
          Shellwords.escape(output_base)
        ].join(' ')

        stdout, stderr, status = Open3.capture3(command)

        expect(status.success?).to(be(true))
        expect(stdout).to(eq(''))
        expect(stderr).to(eq(''))

        html_path = "#{output_base}.html"
        json_path = "#{output_base}.json"
        pdf_path = "#{output_base}.pdf"

        expect(File.exist?(html_path)).to(eq(true))
        expect(File.exist?(json_path)).to(eq(true))
        expect(File.exist?(pdf_path)).to(eq(true))

        html = File.read(html_path)
        json = JSON.parse(File.read(json_path))
        pdf = File.binread(pdf_path)

        expect(html).to(includes('<html>'))
        expect(html).to(includes('<nav class="report-index"'))
        expect(html).to(includes('href="#ctx-1"'))
        expect(html).to(includes('href="#test-1"'))
        expect(html).to(includes('href="#pending-1"'))
        expect(json['format']).to(eq('prd-json-v1'))
        expect(pdf.start_with?('%PDF-')).to(eq(true))
        expect(pdf).to(includes('Index'))
        expect(pdf).to(includes('/Dest'))
        expect(pdf).to(includes('ctx-1'))
        expect(pdf).to(includes('test-1'))
        expect(pdf).to(includes('pending-1'))
      end
    ensure
      spec_file.close!
    end
  end

  it 'writes report to default report name when --out points to a directory' do
    spec_file = Tempfile.new(['prd_cli_out_dir', '_spec.rb'])
    begin
      spec_file.write(<<~SPEC)
        describe 'CLI output dir suite' do
          it 'works' do
            expect(1).to(eq(1))
          end
        end
      SPEC
      spec_file.flush

      Dir.mktmpdir('prd_out_dir') do |tmp_dir|
        out_dir = File.join(tmp_dir, 'reports')
        Dir.mkdir(out_dir)

        command = [
          'bundle exec ruby bin/prd',
          Shellwords.escape(spec_file.path),
          '-t json',
          '--out',
          Shellwords.escape(out_dir)
        ].join(' ')

        stdout, stderr, status = Open3.capture3(command)

        expect(status.success?).to(be(true))
        expect(stdout).to(eq(''))
        expect(stderr).to(eq(''))

        json_path = File.join(out_dir, 'report.json')
        expect(File.exist?(json_path)).to(eq(true))

        payload = JSON.parse(File.read(json_path))
        expect(payload['format']).to(eq('prd-json-v1'))
      end
    ensure
      spec_file.close!
    end
  end

  it 'writes simple formatter output as .txt when --out points to a directory' do
    spec_file = Tempfile.new(['prd_cli_simple_out_dir', '_spec.rb'])
    begin
      spec_file.write(<<~SPEC)
        describe 'CLI simple output dir suite' do
          it 'works' do
            expect(1).to(eq(1))
          end
        end
      SPEC
      spec_file.flush

      Dir.mktmpdir('prd_simple_out_dir') do |tmp_dir|
        out_dir = File.join(tmp_dir, 'reports')
        Dir.mkdir(out_dir)

        command = [
          'bundle exec ruby bin/prd',
          Shellwords.escape(spec_file.path),
          '--out',
          Shellwords.escape(out_dir)
        ].join(' ')

        stdout, stderr, status = Open3.capture3(command)

        expect(status.success?).to(be(true))
        expect(stdout).to(eq(''))
        expect(stderr).to(eq(''))

        report_path = File.join(out_dir, 'report.txt')
        expect(File.exist?(report_path)).to(eq(true))

        report = File.read(report_path)
        expect(report).to(includes('1 passed, 0 failed'))
      end
    ensure
      spec_file.close!
    end
  end

  it 'generates minimal valid HTML output' do
    io = StringIO.new
    formatter = PrD::Formatters::HtmlFormatter.new(io:, serializers: {})

    PrD::Runtime.new(formatter:, output_dir: nil, config_file: nil).run([
      <<~SPEC
        describe 'HTML suite' do
          it 'works' do
            expect(1).to(eq(1))
          end
        end
      SPEC
    ])

    io.rewind
    html = io.read
    expect(html).to(includes('<html>'))
    expect(html).to(includes('</html>'))
    expect(html).to(includes('<main class="container">'))
    expect(html).to(includes('<strong>1 passed, 0 failed</strong>'))
  end

  it 'adds an internal HTML index with context, test, and pending anchors' do
    io = StringIO.new
    formatter = PrD::Formatters::HtmlFormatter.new(io:, serializers: {})

    PrD::Runtime.new(formatter:, output_dir: nil, config_file: nil).run([
      <<~SPEC
        describe 'HTML indexed suite' do
          context 'Context block' do
            it 'works' do
              expect(1).to(eq(1))
            end

            pending 'later'
          end
        end
      SPEC
    ])

    io.rewind
    html = io.read
    expect(html).to(includes('<nav class="report-index" aria-label="Report index">'))
    expect(html).to(includes('href="#ctx-1"'))
    expect(html).to(includes('href="#ctx-2"'))
    expect(html).to(includes('href="#test-1"'))
    expect(html).to(includes('href="#pending-1"'))
    expect(html).to(includes('id="ctx-1"'))
    expect(html).to(includes('id="ctx-2"'))
    expect(html).to(includes('id="test-1"'))
    expect(html).to(includes('id="pending-1"'))
  end

  it 'escapes HTML content in HtmlFormatter output' do
    io = StringIO.new
    formatter = PrD::Formatters::HtmlFormatter.new(io:, serializers: {})

    PrD::Runtime.new(formatter:, output_dir: nil, config_file: nil).run([
      <<~SPEC
        describe '<script>alert(1)</script>' do
          it 'renders escaped content' do
            expect('<b>unsafe</b>').to(eq('<b>unsafe</b>'))
          end
        end
      SPEC
    ])

    io.rewind
    html = io.read
    expect(html).to(includes('&lt;script&gt;alert(1)&lt;/script&gt;'))
    expect(html).to(includes('&lt;b&gt;unsafe&lt;/b&gt;'))
  end

  it 'handles binary expectations in HtmlFormatter output' do
    io = StringIO.new
    formatter = PrD::Formatters::HtmlFormatter.new(io:, serializers: {})

    PrD::Runtime.new(formatter:, output_dir: nil, config_file: nil).run([
      <<~SPEC
        describe 'HTML binary suite' do
          it 'renders binary safely' do
            bytes = [255, 0, 1].pack('C*')
            expect(bytes).to(eq(bytes))
          end
        end
      SPEC
    ])

    io.rewind
    html = io.read
    expect(html).to(includes('<html>'))
    expect(html).to(includes('<strong>1 passed, 0 failed</strong>'))
  end

  it 'keeps LLM matcher deterministic with a fake client' do
    fake_response = Struct.new(:content).new({ 'justification' => 'Checked locally', 'satisfy' => true })
    fake_client = Object.new
    fake_client.define_singleton_method(:with_instructions) { |_msg| self }
    fake_client.define_singleton_method(:with_params) { |_params| self }
    fake_client.define_singleton_method(:with_schema) { |_schema| self }
    fake_client.define_singleton_method(:ask) { |_prompt, **_kwargs| fake_response }

    matcher = PrD::Matchers::LlmMatcher.new('condition', client: fake_client, timeout_seconds: 1, retries: 0)
    result = matcher.matches?('sample text')

    expect(result.pass).to(eq(true))
    expect(result.comment).to(eq('Checked locally'))
  end

  it 'produces structured JSON formatter output' do
    io = StringIO.new
    formatter = PrD::Formatters::JsonFormatter.new(io:, serializers: {})

    PrD::Runtime.new(formatter:, output_dir: nil, config_file: nil).run([
      <<~SPEC
        describe 'JSON suite' do
          let(:value) { 1 }

          it 'works' do
            expect(value).to(eq(1))
          end
        end
      SPEC
    ])

    io.rewind
    json = JSON.parse(io.read)

    expect(json['format']).to(eq('prd-json-v1'))
    expect(json['summary']['passed']).to(eq(1))
    expect(json['summary']['failed']).to(eq(0))
    expect(json['events'].is_a?(Array)).to(eq(true))
    expect(json['events'].any? { |e| e['type'] == 'matcher' }).to(eq(true))
    expect(json['events'].any? { |e| e['type'] == 'let' }).to(eq(true))
  end

  it 'handles binary expectations in JsonFormatter output' do
    io = StringIO.new
    formatter = PrD::Formatters::JsonFormatter.new(io:, serializers: {})

    PrD::Runtime.new(formatter:, output_dir: nil, config_file: nil).run([
      <<~SPEC
        describe 'JSON binary suite' do
          it 'renders binary safely' do
            bytes = [255, 0, 1].pack('C*')
            expect(bytes).to(eq(bytes))
          end
        end
      SPEC
    ])

    io.rewind
    json = JSON.parse(io.read)
    expect(json['format']).to(eq('prd-json-v1'))
    expect(json['summary']['passed']).to(eq(1))
    expect(json['summary']['failed']).to(eq(0))
  end

  it 'reduces SimpleFormatter output in synthetic mode' do
    io = StringIO.new
    formatter = PrD::Formatters::SimpleFormatter.new(io:, serializers: {}, mode: :synthetic)

    PrD::Runtime.new(formatter:, output_dir: nil, config_file: nil).run([
      <<~SPEC
        describe 'Simple synthetic suite' do
          it 'passes eq' do
            expect(1).to(eq(1))
          end

          it 'fails eq' do
            expect(1).to(eq(2))
          end

          pending 'later'
        end
      SPEC
    ])

    io.rewind
    output = io.read
    expect(output).to(includes('PASS: passes eq'))
    expect(output).to(includes('FAIL: fails eq'))
    expect(output).to(includes('PENDING: later'))
    expect(output).to(includes('1 passed, 1 failed'))
    expect(output).not_to(includes('Expect:'))
    expect(output).not_to(includes('Justification:'))
  end

  it 'reduces HtmlFormatter output in synthetic mode' do
    io = StringIO.new
    formatter = PrD::Formatters::HtmlFormatter.new(io:, serializers: {}, mode: :synthetic)

    PrD::Runtime.new(formatter:, output_dir: nil, config_file: nil).run([
      <<~SPEC
        describe 'HTML synthetic suite' do
          it 'works' do
            expect(1).to(eq(1))
          end

          pending 'later'
        end
      SPEC
    ])

    io.rewind
    html = io.read
    expect(html).to(includes('<h3 class="test-title">works</h3>'))
    expect(html).to(includes("<div class='status success'>PASS</div>"))
    expect(html).to(includes('<h3 class="test-title">later</h3>'))
    expect(html).to(includes("<div class='status pending'>PENDING</div>"))
    expect(html).to(includes('<nav class="report-index"'))
    expect(html).to(includes('href="#ctx-1"'))
    expect(html).to(includes('href="#test-1"'))
    expect(html).to(includes('href="#pending-1"'))
    expect(html).to(includes('<strong>1 passed, 0 failed</strong>'))
    expect(html).not_to(includes('<strong>Expect:</strong>'))
    expect(html).not_to(includes('<strong>Matcher:</strong>'))
  end

  it 'produces compact JSON formatter output in synthetic mode' do
    io = StringIO.new
    formatter = PrD::Formatters::JsonFormatter.new(io:, serializers: {}, mode: :synthetic)

    PrD::Runtime.new(formatter:, output_dir: nil, config_file: nil).run([
      <<~SPEC
        describe 'JSON synthetic suite' do
          it 'works' do
            expect(1).to(eq(1))
          end

          pending 'later'
        end
      SPEC
    ])

    io.rewind
    json = JSON.parse(io.read)
    events = json['events']

    expect(json['summary']['passed']).to(eq(1))
    expect(json['summary']['failed']).to(eq(0))
    expect(events.any? { |e| e['type'] == 'test_result' && e['title'] == 'works' && e['status'] == 'PASS' }).to(eq(true))
    expect(events.any? { |e| e['type'] == 'test_result' && e['title'] == 'later' && e['status'] == 'PENDING' }).to(eq(true))
    expect(events.any? { |e| e['type'] == 'matcher' }).to(eq(false))
    expect(events.any? { |e| e['type'] == 'expect' }).to(eq(false))
  end

  it 'produces a valid PDF report with Prawn formatter' do
    io = StringIO.new
    formatter = PrD::Formatters::PdfFormatter.new(io:, serializers: {})

    PrD::Runtime.new(formatter:, output_dir: nil, config_file: nil).run([
      <<~SPEC
        describe 'PDF suite' do
          it 'works' do
            expect(1).to(eq(1))
          end
        end
      SPEC
    ])

    content = io.string
    expect(content.start_with?('%PDF-')).to(eq(true))
    expect(content.length > 100).to(eq(true))
    expect(content).to(includes('Index'))
    expect(content).to(includes('/Dest'))
    expect(content).to(includes('ctx-1'))
    expect(content).to(includes('test-1'))
  end

  it 'produces a valid compact PDF report in synthetic mode' do
    io = StringIO.new
    formatter = PrD::Formatters::PdfFormatter.new(io:, serializers: {}, mode: :synthetic)

    PrD::Runtime.new(formatter:, output_dir: nil, config_file: nil).run([
      <<~SPEC
        describe 'PDF synthetic suite' do
          it 'works' do
            expect(1).to(eq(1))
          end

          pending 'later'
        end
      SPEC
    ])

    content = io.string
    expect(content.start_with?('%PDF-')).to(eq(true))
    expect(content.length > 100).to(eq(true))
    expect(content).to(includes('Index'))
    expect(content).to(includes('/Dest'))
    expect(content).to(includes('ctx-1'))
    expect(content).to(includes('test-1'))
    expect(content).to(includes('pending-1'))
  end
end
