describe 'All matcher' do
  context 'when actual responds to all?' do
    context 'with only even numbers' do
      subject { [2, 4, 6, 8] }

      it 'passes when all elements satisfy the predicate' do
        expect.to(all(->(n) { n.even? }))
      end
    end

    context 'with at least one odd number' do
      subject { [2, 3, 4] }

      it 'supports not_to when at least one element fails the predicate' do
        expect(subject).not_to(all(->(n) { n.even? }))
      end
    end
  end

  context 'when actual does not respond to all?' do
    subject do
      begin
        expect(123).to(all(->(n) { n > 0 }))
        nil
      rescue => e
        e
      end
    end

    it 'raises NoMethodError' do
      expect(subject.class).to(eq(NoMethodError))
      expect(subject.message).to(includes("undefined method 'all?'"))
    end
  end
end
