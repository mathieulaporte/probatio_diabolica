describe 'Code tests examples' do
  context 'The code of the AllMatcher', model: "codestral-2508" do
    subject {source_code(PrD::Matchers::AllMatcher) }
    it 'should have only 1 responsibility' do
      expect.to satisfy('This code adheres to the single responsibility principle.')
    end

    it "should have a clear name" do
      expect.to satisfy('This class have a clear name.')
    end

    context "#matches?" do
      subject { source_code(PrD::Matchers::AllMatcher.instance_method(:matches?)) }

      it "should always return a TestResult" do
        expect.to satisfy('This method allways return a TestResult')
      end
    end
  end
end
