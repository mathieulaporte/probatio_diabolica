describe 'Have matcher' do
  context 'when include? is available' do
    context 'with arrays' do
      subject { [1, 2, 3] }

      it 'uses include? for arrays' do
        expect.to(have(2))
      end
    end

    context 'with strings' do
      subject { 'abcdef' }

      it 'uses include? for strings' do
        expect.to(have('cd'))
      end
    end
  end

  context 'when include? is not available' do
    subject do
      begin
        expect(nil).to(have(:anything))
        nil
      rescue => e
        e
      end
    end

    it 'raises NoMethodError' do
      expect(subject.class).to(eq(NoMethodError))
      expect(subject.message).to(includes("undefined method 'include?'"))
    end
  end
end
