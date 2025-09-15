describe 'Basic tests examples' do
  it 'should work with basic assertions' do
    expect(true).to(be(true))
  end
  context 'with numbers' do
    puts current_model
    let(:number) { 5 }
    it 'should compare numbers correctly' do
      expect(number).to(eq(5))
    end

    it 'should handle failing tests' do
      expect(number).to(eq(4))
    end

    it 'should accept not equal matcher' do
      expect(number).not_to(eq(4))
    end

    context 'with a subject' do
      subject { 6 }
      it 'should have the correct subject' do
        expect.to be 6
      end
    end
  end
  context 'with strings' do
    let(:greeting) { 'Hello, LLM Spec!' }
    it 'should have the correct greeting' do
      expect(greeting).to(eq('Hello, LLM Spec!'))
    end

    it 'should include a substring' do
      expect(greeting).to(includes('LLM'))
    end
  end

  context 'pending tests' do
    pending 'this test is pending and should not run'
  end

  context 'with llm matcher', model: 'qwen/qwen-2.5-72b-instruct:free' do
    let(:affirmation) { 'The capital of France is Paris.' }
    let(:wrong_affirmation) { 'The capital of France is Berlin.' }

    it 'should pass' do
      expect(affirmation).to(satisfy('This statement is true.'))
    end

    it 'should also pass' do
      expect(wrong_affirmation).not_to(satisfy('This statement is true.'))
    end

    it 'should validate things' do
      expect('Select * from users where id = 1').to(satisfy('This statement is a valid SQL query.'))
    end

    it 'should not validate things' do
      expect('Select * from users where id : 1').to(satisfy('This statement is a valid SQL query.'))
    end
  end
end
