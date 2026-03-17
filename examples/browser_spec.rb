describe 'Browser helpers examples' do
  let(:fixture_url) { "file://#{File.expand_path('examples/browser_fixture.html', Dir.pwd)}" }
  let(:photo_path) { File.expand_path('examples/random_photo.png', Dir.pwd) }

  subject { text(at: fixture_url, css: '#status', warmup_time: 1) }

  it 'extracts dynamic text after JavaScript execution' do
    expect.to(includes('Loaded via JS'))
  end

  context 'with a screenshot', model: "mistral-small-latest"  do
    subject {screen(at: fixture_url, width: 1024, height: 768, warmup_time: 1) }
    it 'captures a screenshot' do
      expect.to satisfy('The screenshot contains the text "browser fixture"')
    end
  end

  it 'returns the rendered html body' do
    rendered = html(at: fixture_url, warmup_time: 1)
    expect(rendered).to(includes('browser fixture'))
  end

  it 'interacts with forms and uploads a file' do
    uploaded_label = nil

    html(at: fixture_url, warmup_time: 1) do |page|
      page.fill(css: '#title', with: 'My upload')
      page.click(css: 'button[data-open-upload]')
      page.set_files(
        css: 'input[type="file"]',
        shadow: ['fixture-scanner', '[data-view="upload"]'],
        path: photo_path
      )
      uploaded_label = page.evaluate(
        "document.querySelector('fixture-scanner').shadowRoot.querySelector('#upload-status').textContent"
      )
    end

    expect(uploaded_label).to(includes('random_photo.png'))
  end

  context 'with a PDF generation' do
    subject { pdf(at: fixture_url, warmup_time: 1) }

    it 'generates a readable pdf with at least one page' do
      expect(subject.pages.length > 0).to(eq(true))
    end
  end

  it 'returns network urls as an array' do
    urls = network_urls(at: fixture_url, warmup_time: 1)
    expect(urls.is_a?(Array)).to(eq(true))
  end
end
