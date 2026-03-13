# Probatio Diabolica

<p align="center">
  <img src="diable.png" alt="Logo Probatio Diabolica" width="260" />
</p>

A Ruby DSL-based testing framework with classic matchers and LLM-powered matchers (text and image).

This project is experimental and not production-ready.

## What this project does

`probatio_diabolica` runs `*_spec.rb` files through a custom runtime (`PrD::Runtime`) with an RSpec-like syntax:

- `describe`, `context`, `it`, `pending`, `let`, `subject`
- `expect(...).to(...)` and `expect(...).not_to(...)`
- standard matchers (`eq`, `be`, `includes`, `have`, `all`)
- LLM matcher `satisfy(...)` to validate natural-language conditions

Tests are evaluated with `instance_eval` (not through RSpec).

## Installation

### From the gem

```ruby
gem 'probatio_diabolica'
```

Then:

```bash
bundle install
```

In Ruby code, you can load it with:

```ruby
require "probatio_diabolica"
```

### From this repository (local development)

```bash
bundle install
bundle exec prd examples/basics_spec.rb
```

### Build and install as a gem

```bash
# build the package
gem build probatio_diabolica.gemspec

# install locally from the built gem
gem install ./probatio_diabolica-*.gem
```

## Release workflow

Use the release helper to bump version, refresh `Gemfile.lock`, create commit/tag, and push:

```bash
# explicit version
bin/release --version 0.2.0

# or env-style
VERSION=0.2.0 bin/release

# semantic bump from current version
bin/release --bump patch
```

Useful options:

- `--dry-run` preview all actions without modifying files/git
- `--no-push` create commit/tag locally only
- `--skip-tests` skip `bundle exec ruby bin/prd spec --mode synthetic`
- `--allow-dirty` bypass clean-working-tree guard

After installation, you can run:

```bash
prd examples/basics_spec.rb
```

If `prd` is not found, add your gem bin directory to `PATH`:

```bash
export PATH="$(ruby -e 'print Gem.user_dir')/bin:$PATH"
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
bundle exec ruby bin/prd examples/basics_spec.rb

# all *_spec.rb files in a directory
bundle exec ruby bin/prd examples

# HTML report in an existing directory (creates ./tmp/report.html)
bundle exec ruby bin/prd examples/image_spec.rb -t html -o ./tmp/

# multiple reports from one run with shared base name
bundle exec ruby bin/prd examples/basics_spec.rb -t html,json,pdf -o ./tmp/my_report

# compact synthetic output on console
bundle exec ruby bin/prd examples/basics_spec.rb --mode synthetic
```

## Available DSL

### Structure

```ruby
describe 'My domain' do
  context 'my context' do
    let(:value) { 5 }
    subject { 'hello' }

    it 'runs an assertion' do
      expect(value).to eq(5)
    end

    pending 'test to implement later'
  end
end
```

### Assertions

- `expect(actual).to matcher`
- `expect(actual).not_to matcher`
- `expect { |subject| ... }.to matcher`
- `expect.to matcher` (uses `subject`)

### Matchers

- `eq(expected)` equality with `==`
- `be(expected)` object identity (`equal?`)
- `includes(expected)` inclusion for `String`, `Array`, `File`, `PDF::Reader`
- `have(expected)` alias inclusion via `include?`
- `all(proc)` checks all elements against a block
- `satisfy(natural_language_condition)` LLM-based validation

### Browser helpers (Ferrum)

`PrD::Runtime` exposes helpers to test content loaded in Chrome:

- `screen(at:, width:, height:, warmup_time:)` captures a PNG and returns a `File`
- `text(at:, css:, warmup_time:)` extracts a CSS node into a `.txt` file and returns a `File`
- `network(at:, warmup_time:)` returns Ferrum network traffic
- `network_urls(at:, warmup_time:)` returns traffic URLs
- `pdf(at:, warmup_time:)` generates a PDF and returns a `PDF::Reader`
- `html(at:, warmup_time:)` returns HTML (`browser.body`)

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

### Subject rendering policy (best effort)

When you define a `subject`, each formatter tries to render it in the most useful way for its medium:

- `SimpleFormatter`:
  - renders readable text in terminal
  - for files, prints a textual representation (for example path, file preview for `.txt`)
- `HtmlFormatter`:
  - renders text values directly
  - for `PrD::Code`, renders syntax-highlighted code blocks (Rouge)
  - for image files (`.png`, `.jpg`, `.jpeg`), embeds the image in the report
  - for PDF subjects (`File` `.pdf` or `PDF::Reader`), embeds the PDF with a `data:application/pdf;base64,...` URI
- `PdfFormatter`:
  - renders text values as report lines
  - for `PrD::Code`, renders language + code block (plain, without syntax colors)
  - for image files (`.png`, `.jpg`, `.jpeg`), inserts the image directly in the PDF report
- `JsonFormatter`:
  - keeps a structured representation for machine processing
  - for `PrD::Code`, emits a structured payload (`type: "code"`, `language`, `source`)
  - `File` values (images, PDFs, text files, etc.) are embedded as base64 payloads
  - `PDF::Reader` values are also embedded as base64 (`application/pdf`)

The goal is to preserve readability and report size while surfacing the richest representation each formatter can reasonably support.

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
