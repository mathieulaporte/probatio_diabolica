describe 'Browser helpers examples' do
  let(:fixture_url) { "file://#{File.expand_path('examples/browser_fixture.html', Dir.pwd)}" }

  it 'extracts dynamic text after JavaScript execution' do
    extracted = text(at: fixture_url, css: '#status', warmup_time: 1)
    expect(extracted).to(includes('Loaded via JS'))
  end

  it 'captures a screenshot' do
    image = screen(at: fixture_url, width: 1024, height: 768, warmup_time: 1)
    expect(File.exist?(image.path)).to(eq(true))
  end

  it 'returns the rendered html body' do
    rendered = html(at: fixture_url, warmup_time: 1)
    expect(rendered).to(includes('browser fixture'))
  end

  it 'generates a readable pdf' do
    document = pdf(at: fixture_url, warmup_time: 1)
    expect(document.pages.length > 0).to(eq(true))
  end

  it 'returns network urls as an array' do
    urls = network_urls(at: fixture_url, warmup_time: 1)
    expect(urls.is_a?(Array)).to(eq(true))
  end
end
