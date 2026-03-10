describe 'Have matcher' do
  context 'when include? is available' do
    it 'uses include? for arrays' do
      expect([1, 2, 3]).to have(2)
    end

    it 'uses include? for strings' do
      expect('abcdef').to have('cd')
    end
  end

  context 'when include? is not available' do
    it 'raises NoMethodError' do
      error = nil
      begin
        expect(nil).to have(:anything)
      rescue => e
        error = e
      end

      expect(error.class).to eq(NoMethodError)
      expect(error.message).to includes("undefined method 'include?'")
    end
  end
end
