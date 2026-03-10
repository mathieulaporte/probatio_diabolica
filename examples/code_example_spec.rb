describe 'Code tests examples' do
  context 'The code of the AllMatcher', model: "codestral-2508" do
    let(:all_matcher_code) do
      source_code(PrD::Matchers::AllMatcher)
    end
    it 'should have only 1 responsibility' do
      expect(all_matcher_code).to satisfy('This code adheres to the single responsibility principle.')
    end

    it "should have a clear name" do
      expect(all_matcher_code).to satisfy('This class have a clear name.')
    end

    context "#matches?" do
      let(:matches_method) { source_code(PrD::Matchers::AllMatcher.instance_method(:matches?)) }

      it "should always return a TestResult" do
        expect(matches_method).to satisfy('This method allways return a TestResult')
      end
    end
  end
end
