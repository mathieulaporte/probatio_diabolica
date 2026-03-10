describe 'All matcher' do
  context 'when actual responds to all?' do
    it 'passes when all elements satisfy the predicate' do
      expect([2, 4, 6, 8]).to all(->(n) { n.even? })
    end

    it 'supports not_to when at least one element fails the predicate' do
      expect([2, 3, 4]).not_to all(->(n) { n.even? })
    end
  end

  context 'when actual does not respond to all?' do
    it 'raises NoMethodError' do
      error = nil
      begin
        expect(123).to all(->(n) { n > 0 })
      rescue => e
        error = e
      end

      expect(error.class).to eq(NoMethodError)
      expect(error.message).to includes("undefined method 'all?'")
    end
  end
end
