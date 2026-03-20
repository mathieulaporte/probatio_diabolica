# Probatio Diabolica

<p align="center">
  <img src="diable.png" alt="Logo Probatio Diabolica" width="260" />
</p>

A Ruby DSL-based testing framework with classic matchers and LLM-powered matchers (text and image).

This project is experimental and not production-ready.

## What this project does

`probatio_diabolica` runs `*_spec.rb` files through a custom runtime (`PrD::Runtime`) with an RSpec-like syntax:

- `describe`, `context`, `it`, `pending`, `let`, `subject`, `subject!`
- `before`, `after`
- `expect(...).to(...)` and `expect(...).not_to(...)`
- standard matchers (`eq`, `be`, `empty`, `gt`, `gte`, `lt`, `lte`, `includes`, `have`, `all`)
- LLM matcher `satisfy(...)` to validate natural-language conditions

Tests are evaluated with `instance_eval` (not through RSpec).

## Installation

### In the Gemfile

```ruby
gem 'probatio_diabolica'
```

Then:

```bash
bundle install
```

## Configuration LLM

The runtime automatically loads `prd_helper.rb` if present (or a file passed with `-c`).

Minimal example:

```ruby
# prd_helper.rb
RubyLLM.configure do |config|
  config.openrouter_api_key = ENV['OPENROUTER_API_KEY']
end
```

Without valid configuration, tests using `satisfy(...)` will fail.

## Running tests

CLI command:

```bash
prd <file_or_directory> [options]
```

From source checkout (without gem install), this is always valid:

```bash
bundle exec ruby bin/prd <file_or_directory> [options]
```

## MCP server (`run_specs`)

A minimal MCP server is available through:

```bash
bundle exec ruby bin/prd_mcp
```

It exposes one tool: `run_specs`.

Input:
- `path` (required): file or directory containing specs
- `config` (optional): same as `-c`
- `out` (optional): same as `-o`
- `formatters` (optional): array of `simple|html|json|pdf` (default: `["simple"]`)
- `mode` (optional): `verbose|synthetic` (default: `synthetic`)

Output (`structuredContent`):
- `ok`, `exit_code`
- `summary` (`passed`, `failed`, `pending`)
- `artifacts` (`base_out`, `reports`, `annex_dir`)
- `logs` (`stdout`, `stderr`)

Options:

- `-c, --config FILE` Ruby config file to require
- `-t, --type TYPE` formatter type(s), default: `simple`
  - supported: `simple`, `html`, `json`, `pdf`
  - can be repeated (`-t html -t json`) or comma-separated (`-t html,json,pdf`)
- `-o, --out PATH` output base path (directory or file-like base name)
- `-m, --mode MODE` output mode, default: `verbose`
  - supported: `verbose`, `synthetic`

Output rules (`--out`):

- No `--out`:
  - one formatter (`simple`, `html`, or `json`): output goes to `stdout`
  - `pdf`: fails (`PDF formatter requires --out`)
  - multiple formatters: fails (`Multiple formatter types require --out`)
- With `--out PATH`:
  - if `PATH` exists as a directory, or ends with `/`, reports are written as `PATH/report.<ext>`
  - otherwise, `PATH` is treated as a base name and reports are written as `PATH.<ext>`
  - if `PATH` ends with one known extension (`.txt`, `.html`, `.json`, `.pdf`), that extension is stripped before generating outputs

Formatter/file extension mapping:

- `simple` -> `.txt`
- `html` -> `.html`
- `json` -> `.json`
- `pdf` -> `.pdf`

Examples:

```bash
# single file
prd examples/basics_spec.rb

# all *_spec.rb files in a directory
prd examples

# HTML report in an existing directory (creates ./tmp/report.html)
prd examples/image_spec.rb -t html -o ./tmp/

# multiple reports from one run with shared base name
prd examples/basics_spec.rb -t html,json,pdf -o ./tmp/my_report

# compact synthetic output on console
prd examples/basics_spec.rb --mode synthetic
```

## Available DSL

It is inspired by RSpec but with a custom runtime and additional features.

### Structure

```ruby
describe 'My domain' do
  context 'my context' do
    before do
      @sum = 0
    end

    let(:two) { 2 }
    let(:three) { 3 }
    subject { two + three }

    it 'runs an assertion' do
      @sum += subject
      expect.to eq(5)
    end

    after do
      expect(@sum).to(eq(5))
    end

    pending 'test to implement later'
  end
end
```

### Assertions

- `expect(actual).to matcher`
- `expect(actual).not_to matcher`
- `expect { |subject| ... }.to matcher`
- `expect.to matcher` (uses `subject` / `subject!`)
- In verbose formatter output, when `actual` or matcher `expected` come from a `let`, the expectation sentence uses the `let` name.
- A failed expectation reports a detailed message (with names/values) in `Justification`.

### Hooks (`before` / `after`)

- `before { ... }` runs before each `it` in the current context and nested contexts
- `after { ... }` runs after each `it` in the current context and nested contexts
- nested order:
  - `before`: outer to inner
  - `after`: inner to outer

### Subject (`subject` vs `subject!`)

- `subject { ... }`: lazy, evaluated on first access in each example, memoized for that example
- `subject! { ... }`: eager, evaluated before each example body (uses an implicit `before`)

### Spec best practices for `subject` (PRD reports)

When a test defines a `subject`, PRD can surface it more clearly in generated reports.
For CLI and integration specs, prefer:

- grouping with explicit `context`
- one `subject` per context for the main action
- assertions written with `expect.to(...)` when the assertion targets `subject`

Example:

```ruby
context 'when CLI receives an unknown formatter type' do
  subject { Open3.capture3('bundle exec ruby bin/prd spec/self_hosted_spec.rb -t unknown') }

  it 'fails fast on unknown formatter type in CLI' do
    _stdout, stderr, status = subject

    expect(status.success?).to(be(false))
    expect(stderr).to(includes('Unsupported formatter type: unknown. Supported: simple, html, json, pdf'))
  end
end
```

For simple value checks, this pattern keeps specs concise:

```ruby
context 'with strings' do
  subject { 'probatio diabolica' }

  it 'matches expected content' do
    expect.to(includes('diabolica'))
  end
end
```

### Matchers

- `eq(expected)` equality with `==`
- `be(expected)` object identity (`equal?`)
- `empty` checks `empty?` on the actual value
- `gt(expected)` strictly greater than (`>`)
- `gte(expected)` greater than or equal (`>=`)
- `lt(expected)` strictly less than (`<`)
- `lte(expected)` less than or equal (`<=`)
- `includes(expected)` inclusion for `String`, `Array`, `File`, `PDF::Reader`
- `have(expected)` alias inclusion via `include?`
- `all(proc)` checks all elements against a block
- `satisfy(natural_language_condition)` LLM-based validation (supports text, single image `File`, or array of image files)

Example:

```ruby
expect(new_image_size).to be gt(0)
```

### Browser helpers (Ferrum)

`PrD::Runtime` exposes helpers to test content loaded in Chrome:

- `page(at:, warmup_time:)` opens a page and returns a `BrowserSession`
- `screen(at:, width:, height:, warmup_time:)` captures a PNG and returns a `File`
- `text(at:, css:, warmup_time:)` extracts a CSS node and returns `PrD::Code` (language: `text`)
- `network(at:, warmup_time:)` returns Ferrum network traffic
- `network_urls(at:, warmup_time:)` returns traffic URLs
- `pdf(at:, warmup_time:)` generates a PDF and returns a `PDF::Reader`
- `html(at:, warmup_time:)` returns HTML (`browser.body`)

Detailed dedicated documentation:
- `docs/chrome_helper.md` (full API contract, inputs/outputs, errors, and LLM-oriented usage patterns)

`BrowserSession` adds high-level page interactions:

- `find(css:/xpath:, wait:, shadow:)`
- `exists?(css:/xpath:, wait:, shadow:)`
- `click(css:/xpath:, wait:, shadow:)`
- `fill(css:/xpath:, with:, clear:, blur:, wait:, shadow:)`
- `select_option(css:, value:/values:, by:, wait:, shadow:)`
- `set_files(css:, path:/paths:, wait:, shadow:)` (alias `upload_files`)
- `navigate(to:, warmup_time:)`

About `shadow:`:

- `shadow:` is an ordered CSS path used to narrow the scope before the target selector.
- Each step can be a shadow host or a regular container.
- If a step has `shadowRoot`, search continues inside it; otherwise search continues inside the matched node.

Prerequisites:

- Chrome/Chromium must be installed.
- The `ferrum` gem is optional and only required for these helpers.
  - Add `gem 'ferrum'` to your Gemfile, or install it with `gem install ferrum`.
  - If it is missing, an explicit `LoadError` is raised on the first browser helper call.

Example:

```ruby
it 'checks dynamic content loaded in browser' do
  page_text = text(at: 'https://example.com', css: 'main')
  expect(page_text).to(includes('Example Domain'))
end
```

Form interaction and file upload example:

```ruby
it 'uploads a file in a shadow-dom form' do
  html(at: 'https://example.com/upload', warmup_time: 2) do |page|
    page.click(css: 'button[data-open-upload]')
    page.fill(css: 'input[name="title"]', with: 'Invoice')
    page.set_files(
      css: 'input[type="file"]',
      shadow: ['vax-scanner', '[data-view="upload"]'],
      path: 'examples/random_photo.png'
    )
  end
end
```

### Source code helper (Prism)

`source_code(...)` uses the `prism` gem to parse Ruby source and extract class/method code.
It returns a `PrD::Code` object:

- `source` (`String`)
- `language` (`String`, default: `ruby`)

Example:

```ruby
let(:code) { source_code(PrD::Matchers::AllMatcher) }

it 'uses raw source text' do
  expect(code.source).to(includes('class AllMatcher'))
end
```

Prerequisites:

- The `prism` gem is optional and only required for `source_code(...)`.
  - Add `gem 'prism'` to your Gemfile, or install it with `gem install prism`.
  - If it is missing, an explicit `LoadError` is raised on the first `source_code(...)` call.

## LLM models

You can set a model at `context` or `it` level:

```ruby
context 'SQL checks', model: 'qwen/qwen-2.5-72b-instruct:free' do
  it 'accepts a valid query' do
    expect('SELECT * FROM users').to satisfy('This statement is valid SQL.')
  end
end
```

The runtime keeps a model stack (`it` can temporarily override the parent `context` model).

## Formatters

- `PrD::Formatters::SimpleFormatter` (text console output)
- `PrD::Formatters::HtmlFormatter` (simple HTML output)
- `PrD::Formatters::JsonFormatter` (structured JSON output)
- `PrD::Formatters::PdfFormatter` (PDF report output)

In CLI usage:

- selecting one formatter writes one output stream/file
- selecting multiple formatters runs tests once and writes one file per formatter
- expectation rendering is sentence-based across human-readable formatters (for example `Expect 321 to be equal to 321`) to reduce vertical noise
- HTML/PDF also emphasize keywords and actual/expected values for faster scanning

### Let/subject rendering policy (best effort)

When you define a `let` or `subject`, each formatter tries to render it in the most useful way for its medium:

- `SimpleFormatter`:
  - renders readable text in terminal
  - prints `Let(:name)` blocks to make fixture values explicit
  - for `Hash`/`Array` subjects, prints one key/index per line with nested indentation
  - for files, prints a textual representation (for example path, file preview for `.txt`)
  - for `Ferrum::Node`, prints a readable summary (`Ferrum::Node <tag#id.class> text="..."`) instead of the Ruby object id
- `HtmlFormatter`:
  - renders `let` values inside collapsed blocks (click to open)
  - renders text values directly
  - for `Hash`/`Array` subjects, renders nested key/value blocks for better readability
  - for `PrD::Code`, renders syntax-highlighted code blocks (Rouge) inside collapsible sections
  - for image files (`.png`, `.jpg`, `.jpeg`), embeds the image in the report
  - for PDF subjects (`File` `.pdf` or `PDF::Reader`), embeds the PDF with a `data:application/pdf;base64,...` URI
  - for `Ferrum::Node`, renders the same readable summary with HTML escaping
- `PdfFormatter`:
  - renders text values as report lines
  - for `Hash`/`Array` subjects, renders nested key/value lines
  - for `PrD::Code`, renders language + syntax-highlighted code block (Rouge -> Prawn colors)
  - for image files (`.png`, `.jpg`, `.jpeg`), inserts the image directly in the PDF report
  - for `Ferrum::Node`, renders the same readable summary in the generated PDF text
- `JsonFormatter`:
  - keeps a structured representation for machine processing
  - includes `name` in `let` events when available
  - preserves nested `Hash`/`Array` structure in event payloads
  - for `PrD::Code`, emits a structured payload (`type: "code"`, `language`, `source`)
  - `File` values (images, PDFs, text files, etc.) are embedded as base64 payloads
  - `PDF::Reader` values are also embedded as base64 (`application/pdf`)
  - for `Ferrum::Node`, emits a structured payload (`type: "ferrum_node"`, `selector`, `text`, `html_preview`, `summary`)

The goal is to preserve readability and report size while surfacing the richest representation each formatter can reasonably support.

Detailed dedicated documentation:
- `docs/let_subject_rendering.md` (rendering pipeline, adapter injection, formatter behavior, compatibility notes)

### Inject custom display adapters

You can inject custom display logic for domain objects that are not natively handled:

```ruby
formatter = PrD::Formatters::HtmlFormatter.new(
  io: $stdout,
  serializers: {},
  display_adapters: {
    MyDomainObject => lambda do |value|
      {
        title: value.name,
        preview: PrD::Code.new(source: value.to_json, language: 'json')
      }
    end
  }
)
```

Rules:

- adapter key (`MyDomainObject` above) can be a class/module, a symbol (duck-typing via `respond_to?`), or a predicate proc
- adapter value must be callable
- adapter output can reuse native display types (`String`, `Hash`, `Array`, `PrD::Code`, `File`, `PDF::Reader`, etc.)
- adapters are applied before default formatter heuristics, so native rendering still applies to the transformed value

## Useful references in this repository

- Basic example: `examples/basics_spec.rb`
- Code analysis example: `examples/code_example_spec.rb`
- Image example: `examples/image_spec.rb`
- Browser example: `examples/browser_spec.rb`
- CLI entrypoint: `bin/prd`
- DSL runtime: `lib/pr_d.rb`

## Current limitations

- Work in progress, API may change.
- `satisfy(...)` requires a configured LLM provider and network access.
- PDF and multi-format output require `--out`.
