describe 'Empty matcher' do
  context 'with empty collections' do
    subject { [] }

    it 'passes for an empty array' do
      expect.to(empty)
    end

    it 'supports be empty syntax' do
      expect(subject).to be empty
    end
  end

  context 'with non-empty values' do
    it 'supports not_to for non-empty strings' do
      expect('abc').not_to(empty)
    end
  end

  context 'when actual does not respond to empty?' do
    subject do
      begin
        expect(123).to(empty)
        nil
      rescue => e
        e
      end
    end

    it 'raises NoMethodError' do
      expect(subject.class).to(eq(NoMethodError))
      expect(subject.message).to(includes("undefined method 'empty?'"))
    end
  end
end
