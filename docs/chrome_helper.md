# Chrome Helper - Detailed Guide

This document explains `PrD::Helpers::ChromeHelper` in a contract-first way so a human or an LLM can use it reliably.

Source of truth:
- `lib/pr_d/helpers/chrome_helper.rb`

## 1) Purpose

`ChromeHelper` gives browser testing primitives to `PrD::Runtime` through Ferrum.

It provides:
- page navigation and interaction (`page`, `BrowserSession`)
- screenshot capture (`screen`)
- text extraction (`text`)
- network capture (`network`, `network_urls`)
- PDF capture (`pdf`)
- HTML extraction (`html`)

## 2) Prerequisites

Required at first browser helper usage:
- `ferrum` gem

If missing, first call raises:
- `LoadError: Browser helpers require the 'ferrum' gem...`

Also used by `pdf` helper:
- `pdf-reader` gem (already required by the project)

## 3) Runtime behavior and lifecycle

- Browser instance is memoized in `@browser` and reused across helper calls in the same runtime.
- `close_chrome_browser` calls `@browser.quit` and resets `@browser = nil`.
- `PrD::Runtime#run` closes browser in `ensure`, so helpers do not leak browser processes after run.

## 4) Artifact storage

Some helpers write files in an annex directory:
- Base dir: `@output_dir` if set, otherwise `<cwd>/tmp`
- Annex dir: `<base_dir>/annex`

Helper outputs:
- `screen` writes `screenshot-<sha256>.png`
- `pdf` writes `pdf-<sha256>.pdf`

Hash keys:
- screenshot hash input: `"#{at}-#{width}-#{height}-#{warmup_time}"`
- pdf hash input: `at`

This means repeated calls with same inputs overwrite same artifact path.

## 5) Public helper API (Runtime-level)

All methods below are mixed into `PrD::Runtime`.

### `page(at:, warmup_time: 2) { |session| ... } -> BrowserSession`

Inputs:
- `at` (String, required): URL to open
- `warmup_time` (Numeric, optional, default `2`): seconds to sleep after navigation
- optional block receives `session` (`BrowserSession`)

Behavior:
- opens URL
- waits `warmup_time`
- yields session if block given

Output:
- returns `BrowserSession`

### `screen(at:, width: 1280, height: 800, warmup_time: 2) { |session| ... } -> File`

Inputs:
- `at` (String, required)
- `width` (Integer, default `1280`)
- `height` (Integer, default `800`)
- `warmup_time` (Numeric, default `2`)
- optional block with `session`

Behavior:
- opens URL, optional interactions in block
- sets viewport
- saves screenshot to annex dir

Output:
- `File` opened in binary mode (`'rb'`)

### `text(at:, css: 'body', warmup_time: 2) { |session| ... } -> PrD::Code`

Inputs:
- `at` (String, required)
- `css` (String, default `'body'`)
- `warmup_time` (Numeric, default `2`)
- optional block with `session`

Behavior:
- opens URL, optional interactions
- finds first matching CSS node (without wait retry here: wait is `0` in internal call)

Output:
- `PrD::Code.new(source: <node_text>, language: 'text')`

Error:
- `ArgumentError: CSS selector not found: <css>`

### `network(at:, warmup_time: 2) { |session| ... } -> Array`

Inputs:
- `at` (String, required)
- `warmup_time` (Numeric, default `2`)
- optional block with `session`

Output:
- `session.browser.network.traffic` (Ferrum traffic objects)

### `network_urls(at:, warmup_time: 2) { |session| ... } -> Array<String>`

Same inputs as `network`.

Output:
- array of request URLs (`network(...).map(&:url)`)

### `pdf(at:, warmup_time: 2) { |session| ... } -> PDF::Reader`

Inputs:
- `at` (String, required)
- `warmup_time` (Numeric, default `2`)
- optional block with `session`

Behavior:
- opens URL, optional interactions
- exports page to PDF artifact in annex dir

Output:
- `PDF::Reader` loaded from generated file

### `html(at:, warmup_time: 2) { |session| ... } -> PrD::Code`

Inputs:
- `at` (String, required)
- `warmup_time` (Numeric, default `2`)
- optional block with `session`

Output:
- `PrD::Code.new(source: browser.body, language: 'html')`

## 6) `BrowserSession` API (interaction layer)

`BrowserSession` wraps Ferrum browser and adds selector ergonomics.

### Selector model

For methods with selectors:
- Use exactly one of `css:` or `xpath:`
- `within:` can scope search to a previously found node
- `shadow:` is only valid with CSS selectors

Errors:
- no selector: `ArgumentError: Provide a selector with 'css:' or 'xpath:'.`
- both selectors: `ArgumentError: Use either 'css:' or 'xpath:', not both.`
- xpath + shadow: `ArgumentError: 'shadow:' can only be used with 'css:' selectors.`

### `navigate(to:, warmup_time: 0) -> self`

- opens URL and optional sleep

### `wait(seconds) -> self`

- sleep helper

### `wait_for(css: nil, xpath: nil, within: nil, shadow: nil, timeout: 2) -> Node`

- alias behavior over `find(..., wait: timeout)`
- raises on timeout (same behavior as `find` with `raise_on_missing: true`)

### `exists?(css: nil, xpath: nil, within: nil, shadow: nil, wait: 0) -> Boolean`

- returns `true` if found in allotted wait

### `find(css: nil, xpath: nil, within: nil, shadow: nil, wait: 2, raise_on_missing: true) -> Node or nil`

- polling wait loop every 0.05s
- returns node if found
- returns `nil` when not found and `raise_on_missing: false`
- raises when not found and `raise_on_missing: true`:
  - `ArgumentError: Selector not found: css=<...>` or `xpath=<...>`

### `click(css: nil, xpath: nil, within: nil, shadow: nil, wait: 2, mode: :left, keys: [], offset: {}, delay: 0) -> Node`

- finds node
- `scroll_into_view`
- clicks with Ferrum options

### `fill(css: nil, xpath: nil, within: nil, shadow: nil, with:, wait: 2, clear: true, blur: false, dispatch_events: true) -> Node`

Behavior:
- focus
- optional clear (`this.value = ''`)
- type string
- optional dispatch `input` and `change` events
- optional blur

### `select_option(css:, within: nil, shadow: nil, value: nil, values: nil, by: :value, wait: 2) -> Node`

Inputs:
- `css` required
- pass either `value:` or `values:`

Error:
- `ArgumentError: select_option requires 'value' or 'values'.`

### `set_files(css:, within: nil, shadow: nil, path: nil, paths: nil, wait: 2, dispatch_events: true) -> Node`
Alias:
- `upload_files`

Behavior:
- validates file paths (expanded from cwd)
- attaches files to input
- optional input/change events

Errors:
- `ArgumentError: set_files requires 'path' or 'paths'.`
- `ArgumentError: File not found: <...>`

### Pass-through to Ferrum

Unknown methods are delegated to underlying browser (`method_missing`), so raw Ferrum APIs remain available.

## 7) Shadow DOM usage

`shadow:` is an ordered array of CSS selectors used as traversal path.

Traversal algorithm:
1. start from `document` (or `within` when provided)
2. for each selector in `shadow`, query node
3. move into `node.shadowRoot` when available, else stay in node
4. query final target selector in resulting scope

Example:
```ruby
html(at: 'https://example.com') do |page|
  page.click(css: 'button.save', shadow: ['my-app', 'settings-panel'])
end
```

## 8) LLM-oriented usage patterns

Use this order for robust flows:
1. `page` or any top-level helper with block
2. inside block: interact via `find/click/fill/select_option/set_files`
3. outside block: assert on returned object (`PrD::Code`, `File`, `PDF::Reader`, arrays)

Prefer explicit waits:
- use `wait:` on selector calls
- or `wait_for(...)` before action

Keep selectors deterministic:
- stable `data-*` attributes
- avoid fragile full-text selectors when possible

## 9) End-to-end examples

### Capture dynamic text after interaction

```ruby
it 'extracts text after loading data' do
  body_text = text(at: 'https://example.com/dashboard', css: '[data-role="content"]') do |page|
    page.click(css: '[data-action="load"]', wait: 3)
    page.wait(0.5)
  end

  expect(body_text).to(includes('Revenue'))
end
```

### Upload file and collect network URLs

```ruby
it 'uploads a file and checks API calls' do
  urls = network_urls(at: 'https://example.com/upload') do |page|
    page.set_files(css: 'input[type="file"]', path: 'examples/random_photo.png')
    page.click(css: '[data-action="submit"]')
    page.wait(1)
  end

  expect(urls).to(includes('https://example.com/api/upload'))
end
```

## 10) Quick reference (I/O map)

- `page` -> `BrowserSession`
- `screen` -> `File` (`.png`)
- `text` -> `PrD::Code` (`language: 'text'`)
- `network` -> `Array` (Ferrum traffic entries)
- `network_urls` -> `Array<String>`
- `pdf` -> `PDF::Reader`
- `html` -> `PrD::Code` (`language: 'html'`)
