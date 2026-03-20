describe 'Comparison matchers' do
  context 'direct matchers' do
    it 'supports gt for strictly greater values' do
      expect(3).to(gt(2))
    end

    it 'supports gte for greater-or-equal values' do
      expect(3).to(gte(3))
    end

    it 'supports lt for strictly lower values' do
      expect(2).to(lt(3))
    end

    it 'supports lte for lower-or-equal values' do
      expect(2).to(lte(2))
    end
  end

  context 'with be alias syntax' do
    subject { 12 }

    it 'supports be gt(...)' do
      expect(subject).to be gt(0)
    end

    it 'supports be gte(...)' do
      expect(subject).to be gte(12)
    end

    it 'supports be lt(...)' do
      expect(subject).to be lt(20)
    end

    it 'supports be lte(...)' do
      expect(subject).to be lte(12)
    end

    it 'supports not_to with be and comparison matchers' do
      expect(subject).not_to be lt(1)
    end
  end
end
