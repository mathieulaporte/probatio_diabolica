describe 'Includes matcher' do
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
      let(:tmp_dir) { File.join(Dir.pwd, 'tmp') }
      let(:path) { File.join(tmp_dir, 'includes_file.txt') }
      subject { File.open(path, 'rb') }

      it 'works with files and rewinds the cursor' do
        Dir.mkdir(tmp_dir) unless Dir.exist?(tmp_dir)
        File.write(path, "line 1\nline 2\nline 3\n")

        begin
          expect.to(includes('line 2'))
          expect(subject.pos).to(eq(0))
        ensure
          subject.close
        end
      end
    end

    context 'with PDF::Reader' do
      let(:tmp_dir) { File.join(Dir.pwd, 'tmp') }
      let(:pdf_path) { File.join(tmp_dir, 'includes_pdf.pdf') }
      subject { PDF::Reader.new(pdf_path) }

      it 'works with PDF::Reader' do
        require 'prawn'
        Dir.mkdir(tmp_dir) unless Dir.exist?(tmp_dir)
        Prawn::Document.generate(pdf_path) { text 'probatio pdf marker' }

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
