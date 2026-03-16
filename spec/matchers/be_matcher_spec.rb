describe 'Be matcher' do
  context 'object identity' do
    let(:value) { +'identity' }
    subject { value }

    it 'passes for the exact same object' do
      expect.to(be(value))
    end

    it 'supports not_to for distinct objects with same content' do
      expect(subject).not_to(be(String.new('abc')))
    end
  end
end
