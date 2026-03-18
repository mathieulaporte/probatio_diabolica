describe 'Includes matcher' do
  let(:fixtures) { File.join(Dir.pwd, 'spec/fixtures') }

  context 'supported inputs' do
    context 'with strings' do
      subject { 'probatio diabolica' }

      it 'works with strings' do
        expect.to(includes('diabolica'))
      end
    end

    context 'with arrays' do
      subject { %w[alpha beta gamma] }

      it 'works with arrays' do
        expect.to(includes('beta'))
      end
    end

    context 'with files' do
      let(:path) { File.join(fixtures, 'includes_file.txt') }
      subject { File.open(path, 'rb') }

      before do
        Dir.mkdir(fixtures) unless Dir.exist?(fixtures)
        File.write(path, "line 1\nline 2\nline 3\n")
      end

      after do
        subject.close unless subject.closed?
      end

      it 'works with files and rewinds the cursor' do
        expect.to(includes('line 2'))
        expect(subject.pos).to(eq(0))
      end
    end

    context 'with PDF::Reader' do
      let(:pdf_path) { File.join(fixtures, 'includes_pdf.pdf') }
      subject { PDF::Reader.new(pdf_path) }

      before do
        require 'prawn'
        Dir.mkdir(fixtures) unless Dir.exist?(fixtures)
        Prawn::Document.generate(pdf_path) { text 'probatio pdf marker' }
      end

      it 'works with PDF::Reader' do
        expect.to(includes('pdf marker'))
      end
    end
  end

  context 'unsupported inputs' do
    subject do
      begin
        expect(123).to(includes('2'))
        nil
      rescue => e
        e
      end
    end

    it 'raises ArgumentError' do
      expect(subject.class).to(eq(ArgumentError))
      expect(subject.message).to(includes('Unsupported type for includes matcher'))
    end
  end
end
