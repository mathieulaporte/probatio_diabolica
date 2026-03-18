require 'stringio'
require 'open3'
require 'json'
require 'tempfile'
require 'tmpdir'
require 'shellwords'
require 'base64'
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
  [PrD::Code.new(source: stdout, language: 'shell'), stderr, status]
end

def build_fake_ferrum_node(tag: 'button', id: 'save', classes: %w[btn primary], text: 'Save changes', html: nil)
  payload = {
    'tag' => tag,
    'id' => id,
    'classes' => classes,
    'text' => text,
    'html' => html || "<#{tag} id=\"#{id}\" class=\"#{classes.join(' ')}\">#{text}</#{tag}>"
  }

  fake_class = Struct.new(:name).new('Ferrum::Node')
  Object.new.tap do |node|
    node.define_singleton_method(:class) { fake_class }
    node.define_singleton_method(:evaluate) { |_script| payload }
  end
end

def build_tiny_png_file
  file = Tempfile.new(['prd_image_fixture', '.png'])
  file.binmode
  file.write(
    Base64.decode64(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/aS8AAAAASUVORK5CYII='
    )
  )
  file.flush
  file
end

def build_formatter_io(formatter_class, mode: :verbose, serializers: {}, display_adapters: {})
  io = StringIO.new
  formatter = formatter_class.new(io:, serializers:, mode:, display_adapters:)
  [formatter, io]
end

def run_runtime_with_formatter(formatter_class, spec_source, mode: :verbose, serializers: {}, display_adapters: {})
  formatter, io = build_formatter_io(
    formatter_class,
    mode:,
    serializers:,
    display_adapters:
  )
  PrD::Runtime.new(formatter:, output_dir: nil, config_file: nil).run([spec_source])
  io.rewind
  io.read
end

def with_temp_spec_file(prefix, content)
  spec_file = Tempfile.new([prefix, '_spec.rb'])
  spec_file.write(content)
  spec_file.flush
  yield spec_file.path
ensure
  spec_file.close! if spec_file
end

CustomDisplayValue = Struct.new(:title, :body, keyword_init: true)

describe 'PrD self-hosted reliability' do
  let(:simple_report) do
    report = run_runtime_with_formatter(
      PrD::Formatters::SimpleFormatter,
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
    )
    PrD::Code.new(source: report, language: 'shell')
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

  it 'supports before and after hooks for each example' do
    output = run_runtime_with_formatter(
      PrD::Formatters::SimpleFormatter,
      <<~SPEC
        describe 'Hooks suite' do
          before do
            @before_count ||= 0
            @before_count += 1
          end

          after do
            @after_count ||= 0
            @after_count += 1
          end

          it 'runs before on first test' do
            expect(@before_count).to(eq(1))
          end

          it 'runs before on second test' do
            expect(@before_count).to(eq(2))
          end

          it 'runs after from previous tests' do
            expect(@after_count).to(eq(2))
          end
        end
      SPEC
    )
    expect(output).to(includes('3 passed, 0 failed'))
  end

  it 'runs nested hooks in deterministic order' do
    output = run_runtime_with_formatter(
      PrD::Formatters::SimpleFormatter,
      <<~SPEC
        describe 'Nested hooks suite' do
          before do
            @events ||= []
            @events << 'outer-before'
          end

          after do
            @events << 'outer-after'
          end

          context 'inner scope' do
            before do
              @events << 'inner-before'
            end

            after do
              @events << 'inner-after'
            end

            it 'applies outer then inner before hooks' do
              expect(@events).to(eq(['outer-before', 'inner-before']))
            end

            it 'applies inner then outer after hooks' do
              expect(@events).to(
                eq(
                  [
                    'outer-before', 'inner-before',
                    'inner-after', 'outer-after',
                    'outer-before', 'inner-before'
                  ]
                )
              )
            end
          end
        end
      SPEC
    )
    expect(output).to(includes('2 passed, 0 failed'))
  end

  it 'evaluates subject lazily and memoizes it per example' do
    output = run_runtime_with_formatter(
      PrD::Formatters::SimpleFormatter,
      <<~SPEC
        describe 'Lazy subject suite' do
          subject do
            @subject_calls ||= 0
            @subject_calls += 1
            { payload: :ok }
          end

          it 'does not evaluate subject before access' do
            expect(@subject_calls.nil?).to(eq(true))
            expect.to(eq({ payload: :ok }))
          end

          it 'memoizes subject within the same example' do
            first = subject
            second = subject
            expect(first.equal?(second)).to(eq(true))
            expect(@subject_calls).to(eq(2))
          end
        end
      SPEC
    )

    expect(output).to(includes('2 passed, 0 failed'))
  end

  it 'supports subject! as eager subject evaluation' do
    output = run_runtime_with_formatter(
      PrD::Formatters::SimpleFormatter,
      <<~SPEC
        describe 'Eager subject suite' do
          subject! do
            @eager_calls ||= 0
            @eager_calls += 1
            'ready'
          end

          it 'evaluates before the example body' do
            expect(@eager_calls).to(eq(1))
            expect.to(eq('ready'))
          end

          it 'runs once per example' do
            expect(@eager_calls).to(eq(2))
            expect.to(eq('ready'))
          end
        end
      SPEC
    )

    expect(output).to(includes('2 passed, 0 failed'))
    expect(output.scan(/Subject/).length).to(eq(1))
  end

  it 'renders lazy subject value when evaluated in examples' do
    output = run_runtime_with_formatter(
      PrD::Formatters::SimpleFormatter,
      <<~SPEC
        describe 'Lazy display suite' do
          subject { 'ready' }

          it 'uses subject once' do
            expect.to(eq('ready'))
          end

          it 'uses subject twice' do
            expect.to(eq('ready'))
          end
        end
      SPEC
    )

    expect(output).not_to(includes('Lazy subject:'))
    expect(output.scan(/Subject/).length).to(eq(2))
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
      with_temp_spec_file('prd_cli_synthetic', <<~SPEC) do |spec_path|
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
        capture_cli("bundle exec ruby bin/prd #{spec_path} --mode synthetic")
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
      with_temp_spec_file('prd_cli_verbose', <<~SPEC) do |spec_path|
          describe 'CLI verbose suite' do
            it 'works' do
              expect(1).to(eq(1))
            end
          end
        SPEC
        capture_cli("bundle exec ruby bin/prd #{spec_path} --mode verbose")
      end
    end

    it 'keeps verbose mode behavior from CLI' do
      stdout, stderr, status = subject

      expect(status.success?).to(be(true))
      expect(stderr).to(eq(''))
      expect(stdout).to(includes('Expect 1 to be equal to 1'))
      expect(stdout).to(includes('Test passed successfully'))
    end
  end

  context 'when CLI generates multiple formatter outputs with --out base path' do
    subject do
      with_temp_spec_file('prd_cli_multi', <<~SPEC) do |spec_path|
          describe 'CLI multi formatter suite' do
            context 'index coverage' do
              it 'works' do
                expect(1).to(eq(1))
              end

              pending 'later'
            end
          end
        SPEC
        Dir.mktmpdir('prd_multi_output') do |tmp_dir|
          output_base = File.join(tmp_dir, 'my_report')
          command = [
            'bundle exec ruby bin/prd',
            Shellwords.escape(spec_path),
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
      with_temp_spec_file('prd_cli_out_dir', <<~SPEC) do |spec_path|
          describe 'CLI output dir suite' do
            it 'works' do
              expect(1).to(eq(1))
            end
          end
        SPEC
        Dir.mktmpdir('prd_out_dir') do |tmp_dir|
          out_dir = File.join(tmp_dir, 'reports')
          Dir.mkdir(out_dir)

          command = [
            'bundle exec ruby bin/prd',
            Shellwords.escape(spec_path),
            '-t json',
            '--out',
            Shellwords.escape(out_dir)
          ].join(' ')

          stdout, stderr, status = capture_cli(command)
          json_path = File.join(out_dir, 'report.json')
          payload = JSON.parse(File.read(json_path)) if File.exist?(json_path)

          { stdout:, stderr:, status:, json_path:, payload: }
        end
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
      with_temp_spec_file('prd_cli_simple_out_dir', <<~SPEC) do |spec_path|
          describe 'CLI simple output dir suite' do
            it 'works' do
              expect(1).to(eq(1))
            end
          end
        SPEC
        Dir.mktmpdir('prd_simple_out_dir') do |tmp_dir|
          out_dir = File.join(tmp_dir, 'reports')
          Dir.mkdir(out_dir)

          command = [
            'bundle exec ruby bin/prd',
            Shellwords.escape(spec_path),
            '--out',
            Shellwords.escape(out_dir)
          ].join(' ')

          stdout, stderr, status = capture_cli(command)
          report_path = File.join(out_dir, 'report.txt')
          report = File.read(report_path) if File.exist?(report_path)

          { stdout:, stderr:, status:, report_path:, report: }
        end
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
    html = run_runtime_with_formatter(
      PrD::Formatters::HtmlFormatter,
      <<~SPEC
        describe 'HTML suite' do
          it 'works' do
            expect(1).to(eq(1))
          end
        end
      SPEC
    )
    expect(html).to(includes('<html>'))
    expect(html).to(includes('</html>'))
    expect(html).to(includes('<main class="container">'))
    expect(html).to(includes('<strong>1 passed, 0 failed</strong>'))
    expect(html).to(includes('class="expectation-keyword"'))
    expect(html).to(includes('class="expectation-value actual"'))
    expect(html).to(includes('class="expectation-value expected"'))
  end

  it 'adds an internal HTML index with context, test, and pending anchors' do
    html = run_runtime_with_formatter(
      PrD::Formatters::HtmlFormatter,
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
    )
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
    html = run_runtime_with_formatter(
      PrD::Formatters::HtmlFormatter,
      <<~SPEC
        describe '<script>alert(1)</script>' do
          it 'renders escaped content' do
            expect('<b>unsafe</b>').to(eq('<b>unsafe</b>'))
          end
        end
      SPEC
    )
    expect(html).to(includes('&lt;script&gt;alert(1)&lt;/script&gt;'))
    expect(html).to(includes('&lt;b&gt;unsafe&lt;/b&gt;'))
  end

  it 'handles binary expectations in HtmlFormatter output' do
    html = run_runtime_with_formatter(
      PrD::Formatters::HtmlFormatter,
      <<~SPEC
        describe 'HTML binary suite' do
          it 'renders binary safely' do
            bytes = [255, 0, 1].pack('C*')
            expect(bytes).to(eq(bytes))
          end
        end
      SPEC
    )
    expect(html).to(includes('<html>'))
    expect(html).to(includes('<strong>1 passed, 0 failed</strong>'))
  end

  it 'renders syntax-highlighted code blocks in HtmlFormatter output' do
    html = run_runtime_with_formatter(
      PrD::Formatters::HtmlFormatter,
      <<~SPEC
        describe 'HTML code suite' do
          let(:snippet) { PrD::Code.new(source: "def greet\\n  'hello'\\nend", language: 'ruby') }

          it 'renders code values' do
            expect(snippet).to(eq(snippet))
          end
        end
      SPEC
    )
    valid =
      html.include?('class="code-block"') &&
      html.include?('class="code-toggle"') &&
      html.include?('class="highlight"') &&
      html.include?('class="code-language"') &&
      html.include?('ruby')
    expect(valid).to(eq(true))
  end

  it 'renders let code blocks in HtmlFormatter output' do
    html = run_runtime_with_formatter(
      PrD::Formatters::HtmlFormatter,
      <<~SPEC
        describe 'HTML let code suite' do
          let(:page_html) { PrD::Code.new(source: "<main>\\n  <h1>Hello</h1>\\n</main>", language: 'html') }

          it 'keeps rendering stable' do
            expect(1).to(eq(1))
          end
        end
      SPEC
    )
    valid =
      html.include?('<details class="let-block">') &&
      html.include?('<summary class="let-toggle">Let(:page_html)</summary>') &&
      html.include?('class="code-language"') &&
      html.include?('&lt;main&gt;') &&
      !html.include?('<details class="let-block" open>')
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
    json_payload = run_runtime_with_formatter(
      PrD::Formatters::JsonFormatter,
      <<~SPEC
        describe 'JSON suite' do
          let(:value) { 1 }

          it 'works' do
            expect(value).to(eq(1))
          end
        end
      SPEC
    )
    json = JSON.parse(json_payload)

    expect(json['format']).to(eq('prd-json-v1'))
    expect(json['summary']['passed']).to(eq(1))
    expect(json['summary']['failed']).to(eq(0))
    expect(json['events'].is_a?(Array)).to(eq(true))
    expect(json['events'].any? { |e| e['type'] == 'matcher' }).to(eq(true))
    expect(json['events'].any? { |e| e['type'] == 'let' }).to(eq(true))
  end

  it 'supports display adapters and let names in JsonFormatter output' do
    spec_source = <<~SPEC
      describe 'JSON adapter suite' do
        let(:payload) { Time.utc(2024, 1, 1, 12, 0, 0) }
        subject { payload }

        it 'keeps custom display payloads structured' do
          expect.to(eq(payload))
        end
      end
    SPEC
    json_payload = run_runtime_with_formatter(
      PrD::Formatters::JsonFormatter,
      spec_source,
      display_adapters: {
        Time => lambda do |value|
          {
            heading: 'Captured at',
            snippet: PrD::Code.new(source: value.utc.strftime('%Y-%m-%d %H:%M:%S UTC'), language: 'text')
          }
        end
      }
    )
    json = JSON.parse(json_payload)
    let_event = json['events'].find { |event| event['type'] == 'let' }
    subject_event = json['events'].find { |event| event['type'] == 'subject' }
    let_payload = let_event && let_event['value']
    subject_payload = subject_event && subject_event['value']

    expect(let_event['name']).to(eq('payload'))
    expect(let_payload['heading']).to(eq('Captured at'))
    expect(let_payload.dig('snippet', 'type')).to(eq('code'))
    expect(let_payload.dig('snippet', 'language')).to(eq('text'))
    expect(subject_payload['heading']).to(eq('Captured at'))
  end

  it 'serializes PrD::Code values in JsonFormatter output' do
    json_payload = run_runtime_with_formatter(
      PrD::Formatters::JsonFormatter,
      <<~SPEC
        describe 'JSON code suite' do
          let(:snippet) { PrD::Code.new(source: "def calc\\n  2\\nend", language: 'ruby') }

          it 'serializes code object payloads' do
            expect(snippet).to(eq(snippet))
          end
        end
      SPEC
    )
    json = JSON.parse(json_payload)
    expect_event = json['events'].find { |event| event['type'] == 'expect' }
    payload = expect_event && expect_event['value']
    valid =
      payload.is_a?(Hash) &&
      payload['type'] == 'code' &&
      payload['language'] == 'ruby' &&
      payload['source'].include?('def calc')
    expect(valid).to(eq(true))
  end

  it 'serializes Ferrum::Node values in JsonFormatter output' do
    io = StringIO.new
    formatter = PrD::Formatters::JsonFormatter.new(io:, serializers: {})
    node = build_fake_ferrum_node

    formatter.subject(node)
    formatter.result(1, 0)
    formatter.flush

    io.rewind
    json = JSON.parse(io.read)
    subject_event = json['events'].find { |event| event['type'] == 'subject' }
    payload = subject_event && subject_event['value']
    valid =
      payload.is_a?(Hash) &&
      payload['type'] == 'ferrum_node' &&
      payload['selector'] == 'button#save.btn.primary' &&
      payload['summary'].include?('Ferrum::Node <button#save.btn.primary>')
    expect(valid).to(eq(true))
  end

  it 'handles binary expectations in JsonFormatter output' do
    json_payload = run_runtime_with_formatter(
      PrD::Formatters::JsonFormatter,
      <<~SPEC
        describe 'JSON binary suite' do
          it 'renders binary safely' do
            bytes = [255, 0, 1].pack('C*')
            expect(bytes).to(eq(bytes))
          end
        end
      SPEC
    )
    json = JSON.parse(json_payload)
    expect(json['format']).to(eq('prd-json-v1'))
    expect(json['summary']['passed']).to(eq(1))
    expect(json['summary']['failed']).to(eq(0))
  end

  it 'reduces SimpleFormatter output in synthetic mode' do
    spec_source = <<~SPEC
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
    output = run_runtime_with_formatter(
      PrD::Formatters::SimpleFormatter,
      spec_source,
      mode: :synthetic
    )
    expect(output).to(includes('PASS: passes eq'))
    expect(output).to(includes('FAIL: fails eq'))
    expect(output).to(includes('PENDING: later'))
    expect(output).to(includes('1 passed, 1 failed'))
    expect(output).not_to(includes('Expect:'))
    expect(output).not_to(includes('Justification:'))
  end

  it 'prints the global summary once with nested describe blocks' do
    output = run_runtime_with_formatter(
      PrD::Formatters::SimpleFormatter,
      <<~SPEC
        describe 'Outer suite' do
          describe 'Inner suite' do
            it 'passes once' do
              expect(1).to(eq(1))
            end
          end
        end
      SPEC
    )
    expect(output).to(includes('1 passed, 0 failed'))
    expect(output.scan(/passed,\s+0 failed/).length).to(eq(1))
  end

  it 'renders code blocks with language in SimpleFormatter output' do
    output = run_runtime_with_formatter(
      PrD::Formatters::SimpleFormatter,
      <<~SPEC
        describe 'Simple code suite' do
          let(:snippet) { PrD::Code.new(source: "def format\\n  :ok\\nend", language: 'ruby') }

          it 'prints code values' do
            expect(snippet).to(eq(snippet))
          end
        end
      SPEC
    )
    valid = output.include?('Expect (ruby code) to be equal to (ruby code)') && output.include?('--- Code Block ---')
    expect(valid).to(eq(true))
  end

  it 'renders Ferrum::Node subjects in SimpleFormatter output' do
    io = StringIO.new
    formatter = PrD::Formatters::SimpleFormatter.new(io:, serializers: {})
    node = build_fake_ferrum_node

    formatter.subject(node)

    io.rewind
    output = io.read
    expect(output).to(includes('Ferrum::Node <button#save.btn.primary> text="Save changes"'))
  end

  it 'renders hash subjects with key/value details in SimpleFormatter output' do
    image_file = build_tiny_png_file
    io = StringIO.new
    formatter = PrD::Formatters::SimpleFormatter.new(io:, serializers: {})

    begin
      formatter.subject(
        {
          screenshot: image_file,
          snippet: PrD::Code.new(source: "def sample\n  :ok\nend", language: 'ruby'),
          state: 'ready'
        }
      )
    ensure
      image_file.close!
    end

    io.rewind
    output = io.read
    expect(output).to(includes('screenshot:'))
    expect(output).to(includes('Image file:'))
    expect(output).to(includes('snippet:'))
    expect(output).to(includes('Code (ruby):'))
    expect(output).to(includes('state:'))
    expect(output).to(includes('ready'))
  end

  it 'supports display adapters for let and subject in SimpleFormatter output' do
    spec_source = <<~SPEC
      describe 'Simple adapter suite' do
        let(:payload) { Time.utc(2024, 1, 1, 12, 0, 0) }
        subject { payload }

        it 'renders adapter output' do
          expect.to(eq(payload))
        end
      end
    SPEC
    output = run_runtime_with_formatter(
      PrD::Formatters::SimpleFormatter,
      spec_source,
      display_adapters: {
        Time => lambda do |value|
          {
            heading: 'Captured at',
            snippet: PrD::Code.new(source: value.utc.strftime('%Y-%m-%d %H:%M:%S UTC'), language: 'text')
          }
        end
      }
    )
    expect(output).to(includes('Let(:payload)'))
    expect(output).to(includes('heading:'))
    expect(output).to(includes('Captured at'))
    expect(output).to(includes('Code (text):'))
    expect(output).to(includes('Subject'))
  end

  it 'handles binary expectations in SimpleFormatter verbose output' do
    spec_source = <<~SPEC
      describe 'Simple binary suite' do
        it 'renders binary safely' do
          bytes = "%PDF-1.3\\n\\xFF\\x00".b
          expect(bytes).to(includes('%PDF-1.3'))
        end
      end
    SPEC
    output = run_runtime_with_formatter(
      PrD::Formatters::SimpleFormatter,
      spec_source,
      mode: :verbose
    )
    expect(output).to(includes('1 passed, 0 failed'))
    expect(output).to(includes('Expect %PDF-1.3'))
  end

  it 'reduces HtmlFormatter output in synthetic mode' do
    spec_source = <<~SPEC
      describe 'HTML synthetic suite' do
        it 'works' do
          expect(1).to(eq(1))
        end

        pending 'later'
      end
    SPEC
    html = run_runtime_with_formatter(
      PrD::Formatters::HtmlFormatter,
      spec_source,
      mode: :synthetic
    )
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

  it 'renders Ferrum::Node subjects in HtmlFormatter output' do
    io = StringIO.new
    formatter = PrD::Formatters::HtmlFormatter.new(io:, serializers: {})
    node = build_fake_ferrum_node

    formatter.subject(node)
    formatter.result(1, 0)
    formatter.flush

    html = io.string
    expect(html).to(includes('Ferrum::Node &lt;button#save.btn.primary&gt; text=&quot;Save changes&quot;'))
  end

  it 'renders hash subjects with nested values in HtmlFormatter output' do
    image_file = build_tiny_png_file
    io = StringIO.new
    formatter = PrD::Formatters::HtmlFormatter.new(io:, serializers: {})

    begin
      formatter.subject(
        {
          screenshot: image_file,
          snippet: PrD::Code.new(source: "def html_hash\n  :ok\nend", language: 'ruby'),
          metadata: { status: 'ok' }
        }
      )
      formatter.result(1, 0)
      formatter.flush
    ensure
      image_file.close!
    end

    html = io.string
    expect(html).to(includes('<strong>screenshot:</strong>'))
    expect(html).to(includes('class="subject-image'))
    expect(html).to(includes('<strong>snippet:</strong>'))
    expect(html).to(includes('class="code-block"'))
    expect(html).to(includes('<strong>metadata:</strong>'))
    expect(html).to(includes('<strong>status:</strong>'))
    expect(html).to(includes('ok'))
  end

  it 'supports display adapters for subject values in HtmlFormatter output' do
    io = StringIO.new
    formatter = PrD::Formatters::HtmlFormatter.new(
      io:,
      serializers: {},
      display_adapters: {
        CustomDisplayValue => lambda do |value|
          {
            heading: value.title,
            snippet: PrD::Code.new(source: value.body, language: 'html')
          }
        end
      }
    )

    formatter.subject(CustomDisplayValue.new(title: 'Checkout', body: "<section>ok</section>"))
    formatter.result(1, 0)
    formatter.flush

    html = io.string
    expect(html).to(includes('<strong>heading:</strong>'))
    expect(html).to(includes('Checkout'))
    expect(html).to(includes('class="code-block"'))
  end

  it 'produces compact JSON formatter output in synthetic mode' do
    spec_source = <<~SPEC
      describe 'JSON synthetic suite' do
        it 'works' do
          expect(1).to(eq(1))
        end

        pending 'later'
      end
    SPEC
    json_payload = run_runtime_with_formatter(
      PrD::Formatters::JsonFormatter,
      spec_source,
      mode: :synthetic
    )
    json = JSON.parse(json_payload)
    events = json['events']

    expect(json['summary']['passed']).to(eq(1))
    expect(json['summary']['failed']).to(eq(0))
    expect(events.any? { |e| e['type'] == 'test_result' && e['title'] == 'works' && e['status'] == 'PASS' }).to(eq(true))
    expect(events.any? { |e| e['type'] == 'test_result' && e['title'] == 'later' && e['status'] == 'PENDING' }).to(eq(true))
    expect(events.any? { |e| e['type'] == 'matcher' }).to(eq(false))
    expect(events.any? { |e| e['type'] == 'expect' }).to(eq(false))
  end

  it 'produces a valid PDF report with Prawn formatter' do
    content = run_runtime_with_formatter(
      PrD::Formatters::PdfFormatter,
      <<~SPEC
        describe 'PDF suite' do
          it 'works' do
            expect(1).to(eq(1))
          end
        end
      SPEC
    )
    expect(content.start_with?('%PDF-')).to(eq(true))
    expect(content.length > 100).to(eq(true))
    expect(content).to(includes('Index'))
    expect(content).to(includes('/Dest'))
    expect(content).to(includes('ctx-1'))
    expect(content).to(includes('test-1'))
    reader = PDF::Reader.new(StringIO.new(content))
    text = reader.pages.map(&:text).join("\n")
    expect(text).to(includes('Expect 1 to be equal to 1'))
  end

  it 'renders Ferrum::Node subjects in PdfFormatter output' do
    io = StringIO.new
    formatter = PrD::Formatters::PdfFormatter.new(io:, serializers: {})
    node = build_fake_ferrum_node

    formatter.subject(node)
    formatter.result(1, 0)
    formatter.flush

    reader = PDF::Reader.new(StringIO.new(io.string))
    text = reader.pages.map(&:text).join("\n")
    expect(text).to(includes('Ferrum::Node <button#save.btn.primary> text="Save changes"'))
  end

  it 'renders hash subjects with key/value details in PdfFormatter output' do
    image_file = build_tiny_png_file
    io = StringIO.new
    formatter = PrD::Formatters::PdfFormatter.new(io:, serializers: {})

    begin
      formatter.subject(
        {
          screenshot: image_file,
          snippet: PrD::Code.new(source: "def pdf_hash\n  :ok\nend", language: 'ruby'),
          metadata: { status: 'ok' }
        }
      )
      formatter.result(1, 0)
      formatter.flush
    ensure
      image_file.close!
    end

    content = io.string
    reader = PDF::Reader.new(StringIO.new(content))
    text = reader.pages.map(&:text).join("\n")
    expect(text).to(includes('screenshot:'))
    expect(text).to(includes('Image file:'))
    expect(text).to(includes('snippet:'))
    expect(text).to(includes('Language: ruby'))
    expect(text).to(includes('metadata:'))
    expect(text).to(includes('status:'))
    expect(text).to(includes('ok'))
    expect(content).to(includes('/Subtype /Image'))
  end

  it 'supports display adapters for subject values in PdfFormatter output' do
    io = StringIO.new
    formatter = PrD::Formatters::PdfFormatter.new(
      io:,
      serializers: {},
      display_adapters: {
        CustomDisplayValue => lambda do |value|
          {
            heading: value.title,
            snippet: PrD::Code.new(source: value.body, language: 'html')
          }
        end
      }
    )

    formatter.subject(CustomDisplayValue.new(title: 'Checkout', body: "<section>ok</section>"))
    formatter.result(1, 0)
    formatter.flush

    reader = PDF::Reader.new(StringIO.new(io.string))
    text = reader.pages.map(&:text).join("\n")
    expect(text).to(includes('heading:'))
    expect(text).to(includes('Checkout'))
    expect(text).to(includes('Language: html'))
  end

  it 'renders code blocks with language markers in PdfFormatter output' do
    content = run_runtime_with_formatter(
      PrD::Formatters::PdfFormatter,
      <<~SPEC
        describe 'PDF code suite' do
          let(:snippet) { PrD::Code.new(source: "def pdf\\n  true\\nend", language: 'ruby') }

          it 'renders code values' do
            expect(snippet).to(eq(snippet))
          end
        end
      SPEC
    )
    reader = PDF::Reader.new(StringIO.new(content))
    text = reader.pages.map(&:text).join("\n")
    valid =
      text.include?('Expect (ruby code) to be equal to (ruby code)') &&
      text.include?('Actual code (ruby)') &&
      text.include?('Expected code (ruby)')
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
    spec_source = <<~SPEC
      describe 'PDF synthetic suite' do
        it 'works' do
          expect(1).to(eq(1))
        end

        pending 'later'
      end
    SPEC
    content = run_runtime_with_formatter(
      PrD::Formatters::PdfFormatter,
      spec_source,
      mode: :synthetic
    )
    expect(content.start_with?('%PDF-')).to(eq(true))
    expect(content.length > 100).to(eq(true))
    expect(content).to(includes('Index'))
    expect(content).to(includes('/Dest'))
    expect(content).to(includes('ctx-1'))
    expect(content).to(includes('test-1'))
    expect(content).to(includes('pending-1'))
  end
end
