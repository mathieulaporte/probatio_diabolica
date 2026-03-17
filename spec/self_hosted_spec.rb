require 'stringio'
require 'open3'
require 'json'
require 'tempfile'
require 'tmpdir'
require 'shellwords'
require 'pdf-reader'

def capture_stderr
  previous_stderr = $stderr
  buffer = StringIO.new
  $stderr = buffer
  yield
ensure
  $stderr = previous_stderr
end

def capture_cli(command)
  stdout, stderr, status = Open3.capture3(command)
  [PrD::Code.new(source: stdout, language: 'bash'), stderr, status]
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

  context 'when CLI receives an unknown formatter type' do
    subject { capture_cli('bundle exec ruby bin/prd spec/self_hosted_spec.rb -t unknown') }

    it 'fails fast on unknown formatter type in CLI' do
      _stdout, stderr, status = subject

      expect(status.success?).to(be(false))
      expect(stderr).to(includes('Unsupported formatter type: unknown. Supported: simple, html, json, pdf'))
    end
  end

  context 'when CLI receives an unknown output mode' do
    subject { capture_cli('bundle exec ruby bin/prd spec/self_hosted_spec.rb --mode compact') }

    it 'fails fast on unknown output mode in CLI' do
      _stdout, stderr, status = subject

      expect(status.success?).to(be(false))
      expect(stderr).to(includes('Unsupported mode: compact. Supported: verbose, synthetic'))
    end
  end

  context 'when CLI receives a missing path' do
    subject { capture_cli('bundle exec ruby bin/prd ./spec/does_not_exist_spec.rb') }

    it 'fails fast on missing CLI path' do
      _stdout, stderr, status = subject

      expect(status.success?).to(be(false))
      expect(stderr).to(includes('Path not found: ./spec/does_not_exist_spec.rb'))
    end
  end

  context 'when CLI runs in synthetic mode' do
    subject do
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

        capture_cli("bundle exec ruby bin/prd #{spec_file.path} --mode synthetic")
      ensure
        spec_file.close!
      end
    end

    it 'supports synthetic mode from CLI with compact output' do
      stdout, stderr, status = subject

      expect(status.success?).to(be(false))
      expect(stderr).to(eq(''))
      expect(stdout).to(includes('PASS: passes'))
      expect(stdout).to(includes('FAIL: fails'))
      expect(stdout).to(includes('PENDING: later'))
      expect(stdout).to(includes('1 passed, 1 failed'))
      expect(stdout).not_to(includes('Expect:'))
      expect(stdout).not_to(includes('Justification:'))
    end
  end

  context 'when CLI runs in verbose mode' do
    subject do
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

        capture_cli("bundle exec ruby bin/prd #{spec_file.path} --mode verbose")
      ensure
        spec_file.close!
      end
    end

    it 'keeps verbose mode behavior from CLI' do
      stdout, stderr, status = subject

      expect(status.success?).to(be(true))
      expect(stderr).to(eq(''))
      expect(stdout).to(includes('Expect:'))
      expect(stdout).to(includes('Test passed successfully'))
    end
  end

  context 'when CLI generates multiple formatter outputs with --out base path' do
    subject do
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

          stdout, stderr, status = capture_cli(command)
          html_path = "#{output_base}.html"
          json_path = "#{output_base}.json"
          pdf_path = "#{output_base}.pdf"

          {
            stdout:,
            stderr:,
            status:,
            html_exists: File.exist?(html_path),
            json_exists: File.exist?(json_path),
            pdf_exists: File.exist?(pdf_path),
            html: File.read(html_path),
            json: JSON.parse(File.read(json_path)),
            pdf: File.binread(pdf_path)
          }
        end
      ensure
        spec_file.close!
      end
    end

    it 'generates multiple report formats from CLI with a shared output base path' do
      expect(subject[:status].success?).to(be(true))
      expect(subject[:stdout]).to(eq(''))
      expect(subject[:stderr]).to(eq(''))

      expect(subject[:html_exists]).to(eq(true))
      expect(subject[:json_exists]).to(eq(true))
      expect(subject[:pdf_exists]).to(eq(true))

      expect(subject[:html]).to(includes('<html>'))
      expect(subject[:html]).to(includes('<nav class="report-index"'))
      expect(subject[:html]).to(includes('href="#ctx-1"'))
      expect(subject[:html]).to(includes('href="#test-1"'))
      expect(subject[:html]).to(includes('href="#pending-1"'))
      expect(subject[:json]['format']).to(eq('prd-json-v1'))
      expect(subject[:pdf].start_with?('%PDF-')).to(eq(true))
      expect(subject[:pdf]).to(includes('Index'))
      expect(subject[:pdf]).to(includes('/Dest'))
      expect(subject[:pdf]).to(includes('ctx-1'))
      expect(subject[:pdf]).to(includes('test-1'))
      expect(subject[:pdf]).to(includes('pending-1'))
    end
  end

  context 'when --out points to a directory for json formatter' do
    subject do
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

          stdout, stderr, status = capture_cli(command)
          json_path = File.join(out_dir, 'report.json')
          payload = JSON.parse(File.read(json_path)) if File.exist?(json_path)

          { stdout:, stderr:, status:, json_path:, payload: }
        end
      ensure
        spec_file.close!
      end
    end

    it 'writes report to default report name when --out points to a directory' do
      expect(subject[:status].success?).to(be(true))
      expect(subject[:stdout]).to(eq(''))
      expect(subject[:stderr]).to(eq(''))
      expect(File.exist?(subject[:json_path])).to(eq(true))
      expect(subject[:payload]['format']).to(eq('prd-json-v1'))
    end
  end

  context 'when --out points to a directory for simple formatter' do
    subject do
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

          stdout, stderr, status = capture_cli(command)
          report_path = File.join(out_dir, 'report.txt')
          report = File.read(report_path) if File.exist?(report_path)

          { stdout:, stderr:, status:, report_path:, report: }
        end
      ensure
        spec_file.close!
      end
    end

    it 'writes simple formatter output as .txt when --out points to a directory' do
      expect(subject[:status].success?).to(be(true))
      expect(subject[:stdout]).to(eq(''))
      expect(subject[:stderr]).to(eq(''))
      expect(File.exist?(subject[:report_path])).to(eq(true))
      expect(subject[:report]).to(includes('1 passed, 0 failed'))
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

  it 'renders syntax-highlighted code blocks in HtmlFormatter output' do
    io = StringIO.new
    formatter = PrD::Formatters::HtmlFormatter.new(io:, serializers: {})

    PrD::Runtime.new(formatter:, output_dir: nil, config_file: nil).run([
      <<~SPEC
        describe 'HTML code suite' do
          let(:snippet) { PrD::Code.new(source: "def greet\\n  'hello'\\nend", language: 'ruby') }

          it 'renders code values' do
            expect(snippet).to(eq(snippet))
          end
        end
      SPEC
    ])

    io.rewind
    html = io.read
    valid =
      html.include?('class="code-block"') &&
      html.include?('class="code-toggle"') &&
      html.include?('class="highlight"') &&
      html.include?('class="code-language"') &&
      html.include?('ruby')
    expect(valid).to(eq(true))
  end

  it 'renders let code blocks in HtmlFormatter output' do
    io = StringIO.new
    formatter = PrD::Formatters::HtmlFormatter.new(io:, serializers: {})

    PrD::Runtime.new(formatter:, output_dir: nil, config_file: nil).run([
      <<~SPEC
        describe 'HTML let code suite' do
          let(:page_html) { PrD::Code.new(source: "<main>\\n  <h1>Hello</h1>\\n</main>", language: 'html') }

          it 'keeps rendering stable' do
            expect(1).to(eq(1))
          end
        end
      SPEC
    ])

    io.rewind
    html = io.read
    valid =
      html.include?('<strong>Let:</strong>') &&
      html.include?('class="code-language"') &&
      html.include?('&lt;main&gt;')
    expect(valid).to(eq(true))
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

  it 'supports LLM matcher with PrD::Code inputs' do
    fake_response = Struct.new(:content).new({ 'justification' => 'Checked code', 'satisfy' => true })
    fake_client = Object.new
    fake_client.define_singleton_method(:with_instructions) { |_msg| self }
    fake_client.define_singleton_method(:with_params) { |_params| self }
    fake_client.define_singleton_method(:with_schema) { |_schema| self }
    fake_client.define_singleton_method(:ask) { |_prompt, **_kwargs| fake_response }

    matcher = PrD::Matchers::LlmMatcher.new('condition', client: fake_client, timeout_seconds: 1, retries: 0)
    result = matcher.matches?(PrD::Code.new(source: 'def value; 1; end', language: 'ruby'))

    valid = result.pass == true && result.comment == 'Checked code'
    expect(valid).to(eq(true))
  end

  it 'returns PrD::Code from source_code helper when available' do
    prism_available = true
    begin
      require 'prism'
    rescue LoadError
      prism_available = false
    end

    if prism_available
      class_code = source_code(PrD::Matchers::AllMatcher)
      method_code = source_code(PrD::Matchers::AllMatcher.instance_method(:matches?))
      valid =
        class_code.is_a?(PrD::Code) &&
        method_code.is_a?(PrD::Code) &&
        class_code.language == 'ruby' &&
        method_code.language == 'ruby' &&
        class_code.source.include?('class AllMatcher') &&
        method_code.source.include?('def matches?')
      expect(valid).to(eq(true))
    else
      error_message = begin
        source_code(PrD::Matchers::AllMatcher)
        nil
      rescue LoadError => e
        e.message
      end
      expect(error_message).to(includes("Source code helpers require the 'prism' gem."))
    end
  end

  it 'provides browser interaction helpers for click/fill/select/upload' do
    fake_node = Class.new do
      attr_reader :clicked_with, :typed_text, :evaluations, :selected_values, :selected_by, :selected_files, :blurred

      def initialize
        @evaluations = []
      end

      def scroll_into_view
        self
      end

      def click(**kwargs)
        @clicked_with = kwargs
        self
      end

      def focus
        self
      end

      def evaluate(expression)
        @evaluations << expression
        nil
      end

      def type(value)
        @typed_text = value
        self
      end

      def blur
        @blurred = true
        self
      end

      def select(*values, by:)
        @selected_values = values
        @selected_by = by
        self
      end

      def select_file(value)
        @selected_files = value
        self
      end
    end.new

    fake_browser = Class.new do
      attr_reader :last_css, :last_xpath, :shadow_queries

      def initialize(node)
        @node = node
        @shadow_queries = []
      end

      def at_css(selector)
        @last_css = selector
        @node
      end

      def at_xpath(selector)
        @last_xpath = selector
        @node
      end

      def evaluate_func(function, *args)
        @shadow_queries << { function:, args: }
        @node
      end

      def evaluate(_expression)
        'delegated'
      end
    end.new(fake_node)

    session = PrD::Helpers::ChromeHelper::BrowserSession.new(fake_browser)
    session.click(css: 'button[type="submit"]')
    session.fill(css: '#email', with: 'ada@example.com', blur: true)
    session.select_option(css: 'select#size', value: 'M')
    session.set_files(
      css: 'input[type="file"]',
      shadow: ['vax-scanner', '[data-view="upload"]'],
      path: 'examples/random_photo.png'
    )
    delegated = session.evaluate('window.location.href')

    expected_path = File.expand_path('examples/random_photo.png', Dir.pwd)
    valid =
      fake_node.clicked_with[:mode] == :left &&
      fake_node.typed_text == 'ada@example.com' &&
      fake_node.blurred == true &&
      fake_node.selected_values == ['M'] &&
      fake_node.selected_by == :value &&
      fake_node.selected_files == [expected_path] &&
      fake_browser.shadow_queries.length == 1 &&
      delegated == 'delegated'
    expect(valid).to(eq(true))
  end

  it 'yields a BrowserSession in html blocks while keeping browser API access' do
    fake_browser = Class.new do
      attr_reader :urls, :evaluated

      def initialize
        @urls = []
      end

      def go_to(url)
        @urls << url
      end

      def evaluate(expression)
        @evaluated = expression
        true
      end

      def body
        '<main>ok</main>'
      end
    end.new

    helper_host = Object.new
    helper_host.extend(PrD::Helpers::ChromeHelper)
    helper_host.instance_variable_set(:@output_dir, nil)
    helper_host.define_singleton_method(:chrome_browser) { fake_browser }

    yielded_session = nil
    rendered = helper_host.html(at: 'https://example.test', warmup_time: 0) do |session|
      yielded_session = session
      session.navigate(to: 'https://example.test/upload')
      session.evaluate('window.__uploaded = true')
    end

    valid =
      yielded_session.is_a?(PrD::Helpers::ChromeHelper::BrowserSession) &&
      fake_browser.urls == ['https://example.test', 'https://example.test/upload'] &&
      fake_browser.evaluated == 'window.__uploaded = true' &&
      rendered.source.include?('<main>ok</main>')
    expect(valid).to(eq(true))
  end

  it 'supports includes matcher with PrD::Code' do
    code = PrD::Code.new(source: "alpha\\nbeta", language: 'ruby')
    expect(code).to(includes('beta'))
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

  it 'serializes PrD::Code values in JsonFormatter output' do
    io = StringIO.new
    formatter = PrD::Formatters::JsonFormatter.new(io:, serializers: {})

    PrD::Runtime.new(formatter:, output_dir: nil, config_file: nil).run([
      <<~SPEC
        describe 'JSON code suite' do
          let(:snippet) { PrD::Code.new(source: "def calc\\n  2\\nend", language: 'ruby') }

          it 'serializes code object payloads' do
            expect(snippet).to(eq(snippet))
          end
        end
      SPEC
    ])

    io.rewind
    json = JSON.parse(io.read)
    expect_event = json['events'].find { |event| event['type'] == 'expect' }
    payload = expect_event && expect_event['value']
    valid =
      payload.is_a?(Hash) &&
      payload['type'] == 'code' &&
      payload['language'] == 'ruby' &&
      payload['source'].include?('def calc')
    expect(valid).to(eq(true))
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

  it 'renders code blocks with language in SimpleFormatter output' do
    io = StringIO.new
    formatter = PrD::Formatters::SimpleFormatter.new(io:, serializers: {})

    PrD::Runtime.new(formatter:, output_dir: nil, config_file: nil).run([
      <<~SPEC
        describe 'Simple code suite' do
          let(:snippet) { PrD::Code.new(source: "def format\\n  :ok\\nend", language: 'ruby') }

          it 'prints code values' do
            expect(snippet).to(eq(snippet))
          end
        end
      SPEC
    ])

    io.rewind
    output = io.read
    valid = output.include?('Expect (ruby):') && output.include?('--- Code Block ---')
    expect(valid).to(eq(true))
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

  it 'renders code blocks with language markers in PdfFormatter output' do
    io = StringIO.new
    formatter = PrD::Formatters::PdfFormatter.new(io:, serializers: {})

    PrD::Runtime.new(formatter:, output_dir: nil, config_file: nil).run([
      <<~SPEC
        describe 'PDF code suite' do
          let(:snippet) { PrD::Code.new(source: "def pdf\\n  true\\nend", language: 'ruby') }

          it 'renders code values' do
            expect(snippet).to(eq(snippet))
          end
        end
      SPEC
    ])

    content = io.string
    reader = PDF::Reader.new(StringIO.new(content))
    text = reader.pages.map(&:text).join("\n")
    valid = text.include?('Expect (ruby)') && text.include?('Be equal to (ruby)')
    expect(valid).to(eq(true))
  end

  it 'builds colored code fragments for ruby snippets in PdfFormatter' do
    formatter = PrD::Formatters::PdfFormatter.new(io: StringIO.new, serializers: {})
    fragments = formatter.send(:highlighted_code_fragments, "def pdf\n  true\nend", 'ruby')

    expect(fragments.empty?).to(eq(false))
    non_default = fragments.any? { |fragment| fragment[:color] != PrD::Formatters::PdfFormatter::COLORS[:text] }
    expect(non_default).to(eq(true))
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
