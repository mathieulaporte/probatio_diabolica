describe 'Eq matcher' do
  context 'with primitive values' do
    it 'matches equal values' do
      expect(10).to eq(10)
    end

    it 'supports not_to when values differ' do
      expect(10).not_to eq(3)
    end
  end

  context 'with composite objects' do
    it 'matches hashes and arrays deeply via ==' do
      expect({ a: 1, b: [2, 3] }).to eq({ a: 1, b: [2, 3] })
    end
  end
end
