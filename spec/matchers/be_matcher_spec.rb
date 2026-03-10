describe 'Be matcher' do
  context 'object identity' do
    it 'passes for the exact same object' do
      value = +'identity'
      expect(value).to be(value)
    end

    it 'supports not_to for distinct objects with same content' do
      expect('abc').not_to be(String.new('abc'))
    end
  end
end
