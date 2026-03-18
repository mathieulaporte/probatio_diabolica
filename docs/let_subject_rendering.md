# Let/Subject Rendering and Display Adapters

## Goal

This document describes how Probatio Diabolica renders `let` and `subject` values across formatters, and how to inject custom display logic for domain objects.

The objective is:

- keep reports highly readable for humans
- keep JSON output stable and machine-friendly
- allow extension without forking formatters

## Rendering pipeline

When a formatter receives a `let` or `subject` value, rendering follows this flow:

1. Apply a matching display adapter (if any).
2. Build a normalized display tree.
3. Render this tree with formatter-specific capabilities (terminal, HTML, JSON, PDF).

Core implementation lives in:

- `lib/pr_d/formatters/formatter.rb` (`display_node`, adapter registration, shared heuristics)

## Built-in display node types

The shared renderer can normalize values into these internal types:

- `:text` (generic scalar value)
- `:code` (`PrD::Code`, with `language` + `source`)
- `:map` (`Hash`, recursive key/value rendering)
- `:list` (`Array`, recursive index/value rendering)
- `:image` (`File`/path ending in `.png`, `.jpg`, `.jpeg`)
- `:pdf_file` (`File`/path ending in `.pdf`)
- `:pdf_reader` (`PDF::Reader`)

Circular references are rendered as `[Circular reference]` to avoid recursion issues.

## Display adapters API

All formatters accept `display_adapters:` in their constructor:

```ruby
formatter = PrD::Formatters::HtmlFormatter.new(
  io: $stdout,
  serializers: {},
  display_adapters: {
    MyDomainObject => ->(value) do
      {
        title: value.name,
        preview: PrD::Code.new(source: value.to_json, language: 'json')
      }
    end
  }
)
```

Matching keys can be:

- Class/Module (`matcher === value`)
- `Symbol` (`value.respond_to?(symbol)`)
- `Proc` predicate (`proc.call(value)`)

Adapter callable signatures:

- `->(value) { ... }`
- `->(value, formatter) { ... }` if formatter context is needed

You can also register adapters after initialization:

```ruby
formatter.register_display_adapter(Time) do |value|
  { captured_at: value.utc.strftime('%Y-%m-%d %H:%M:%S UTC') }
end
```

## What each formatter does

### SimpleFormatter

- prints `Let(:name)` and `Subject`
- renders nested maps/lists with indentation
- prints code blocks with language marker
- prints image/PDF references as readable lines

### HtmlFormatter

- renders nested blocks with readable key/value structure
- renders `PrD::Code` as collapsible highlighted blocks
- embeds images and PDF payloads when applicable

### PdfFormatter

- renders nested details line by line
- renders code with language + syntax-colored fragments
- embeds images directly in PDF

### JsonFormatter

- preserves nested structures
- emits structured payloads for code/files/PDF reader/Ferrum nodes
- includes `name` for `let` events when available
- keeps stable envelope: `format: "prd-json-v1"`

## Let naming behavior

Runtime now calls formatter `let` with both name and value (`let(:foo)` -> `name: "foo"`).

For backward compatibility, runtime keeps support for legacy custom formatters that still implement `let(value)` only.

## Recommended adapter patterns

- convert custom objects to `Hash`/`Array` for readable nested output
- use `PrD::Code` for payloads that benefit from syntax highlighting
- keep adapter output deterministic for stable reports and tests
- avoid very large binary payloads unless really needed in reports

## Example with runtime

```ruby
formatter = PrD::Formatters::JsonFormatter.new(
  io: STDOUT,
  serializers: {},
  display_adapters: {
    Time => ->(value) do
      {
        heading: 'Captured at',
        snippet: PrD::Code.new(
          source: value.utc.strftime('%Y-%m-%d %H:%M:%S UTC'),
          language: 'text'
        )
      }
    end
  }
)

PrD::Runtime.new(formatter:, output_dir: nil, config_file: nil).run([
  <<~SPEC
    describe 'Adapter example' do
      let(:payload) { Time.utc(2024, 1, 1, 12, 0, 0) }
      subject { payload }

      it 'renders let and subject through adapter' do
        expect.to(eq(payload))
      end
    end
  SPEC
])
```
