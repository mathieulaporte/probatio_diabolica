describe 'Eq matcher' do
  let(:number_value) { 10 }

  context 'with primitive values' do
    subject { number_value }

    it 'matches equal values' do
      expect.to(eq(number_value))
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
