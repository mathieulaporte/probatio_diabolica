# Probatio Diabolica

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

### From this repository (local development)

```bash
bundle install
bundle exec ruby bin/prd -f examples/basics_spec.rb
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

Command:

```bash
bundle exec ruby bin/prd -f <file_or_directory> [options]
```

Supported options:

- `-f, --file FILE` path to a spec file or directory (required)
- `-o, --out DIR` writes output to `DIR/report.qd` (otherwise stdout)
- `-c, --config FILE` Ruby config file to require
- `-t, --type TYPE` formatter type (`simple` by default, `html` supported)

Examples:

```bash
# single file
bundle exec ruby bin/prd -f examples/basics_spec.rb

# all *_spec.rb files in a directory
bundle exec ruby bin/prd -f examples

# HTML report
bundle exec ruby bin/prd -f examples/image_spec.rb -t html -o ./tmp
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

`PrD::Runtime` expose des helpers pour tester du contenu chargé dans Chrome:

- `screen(at:, width:, height:, warmup_time:)` capture PNG et retourne un `File`
- `text(at:, css:, warmup_time:)` extrait un noeud CSS dans un `.txt` et retourne un `File`
- `network(at:, warmup_time:)` retourne le trafic réseau Ferrum
- `network_urls(at:, warmup_time:)` retourne les URLs du trafic
- `pdf(at:, warmup_time:)` génère un PDF et retourne un `PDF::Reader`
- `html(at:, warmup_time:)` retourne le HTML (`browser.body`)

Pré-requis:

- Chrome/Chromium doit être installé.

Exemple:

```ruby
it 'checks dynamic content loaded in browser' do
  page_text = text(at: 'https://example.com', css: 'main')
  expect(page_text).to(includes('Example Domain'))
end
```

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
- `PrD::Formatters::JsonFormatter` exists in code but is not currently exposed by `bin/prd`

### Subject rendering policy (best effort)

When you define a `subject`, each formatter tries to render it in the most useful way for its medium:

- `SimpleFormatter`:
  - renders readable text in terminal
  - for files, prints a textual representation (for example path, file preview for `.txt`)
- `HtmlFormatter`:
  - renders text values directly
  - for image files (`.png`, `.jpg`, `.jpeg`), embeds the image in the report
  - for PDF subjects (`File` `.pdf` or `PDF::Reader`), embeds the PDF with a `data:application/pdf;base64,...` URI
- `PdfFormatter`:
  - renders text values as report lines
  - for image files (`.png`, `.jpg`, `.jpeg`), inserts the image directly in the PDF report
- `JsonFormatter`:
  - keeps a structured representation for machine processing
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
- Strong dependency on an LLM provider for `satisfy`.
- `-o` output is always written to a file named `report.qd`.
