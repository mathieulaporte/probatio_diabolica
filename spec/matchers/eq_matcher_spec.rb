describe 'Eq matcher' do
  context 'with primitive values' do
    subject { 10 }

    it 'matches equal values' do
      expect.to(eq(10))
    end

    it 'supports not_to when values differ' do
      expect(subject).not_to(eq(3))
    end
  end

  context 'with composite objects' do
    subject { { a: 1, b: [2, 3] } }

    it 'matches hashes and arrays deeply via ==' do
      expect.to(eq({ a: 1, b: [2, 3] }))
    end
  end
end
