require 'stringio'
require 'open3'

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

    runtime.run([])
    io.rewind
    output = io.read
    expect(output).to(includes('No tests found. Provide at least one spec content to run.'))
  end

  it 'fails fast on unknown formatter type in CLI' do
    _stdout, stderr, status = Open3.capture3('bundle exec ruby bin/prd -f spec/self_hosted_spec.rb -t unknown')

    expect(status.success?).to(be(false))
    expect(stderr).to(includes('Unsupported formatter type: unknown. Supported: simple, html, json'))
  end

  it 'fails fast on missing CLI path' do
    _stdout, stderr, status = Open3.capture3('bundle exec ruby bin/prd -f ./spec/does_not_exist_spec.rb')

    expect(status.success?).to(be(false))
    expect(stderr).to(includes('Path not found: ./spec/does_not_exist_spec.rb'))
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
end
