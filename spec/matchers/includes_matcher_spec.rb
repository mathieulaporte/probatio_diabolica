describe 'Includes matcher' do
  context 'supported inputs' do
    it 'works with strings' do
      expect('probatio diabolica').to includes('diabolica')
    end

    it 'works with arrays' do
      expect(%w[alpha beta gamma]).to includes('beta')
    end

    it 'works with files and rewinds the cursor' do
      path = File.join(Dir.pwd, 'tmp', 'includes_file.txt')
      File.write(path, "line 1\nline 2\nline 3\n")
      file = File.open(path, 'rb')

      begin
        expect(file).to includes('line 2')
        expect(file.pos).to eq(0)
      ensure
        file.close
      end
    end

    it 'works with PDF::Reader' do
      require 'prawn'
      pdf_path = File.join(Dir.pwd, 'tmp', 'includes_pdf.pdf')
      Prawn::Document.generate(pdf_path) { text 'probatio pdf marker' }

      reader = PDF::Reader.new(pdf_path)
      expect(reader).to includes('pdf marker')
    end
  end

  context 'unsupported inputs' do
    it 'raises ArgumentError' do
      error = nil
      begin
        expect(123).to includes('2')
      rescue => e
        error = e
      end

      expect(error.class).to eq(ArgumentError)
      expect(error.message).to includes('Unsupported type for includes matcher')
    end
  end
end
