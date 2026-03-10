require 'stringio'
require './lib/pr_d'
describe 'Simple example report' do
  context 'with basic expectations', model: 'codestral-2508' do
    subject do
      io = StringIO.new 
      PrD::Runtime.new(formatter: PrD::Formatters::SimpleFormatter.new(io: , serializers: {}), output_dir: nil, config_file: nil).run([File.read('./examples/basics_spec.rb')])
      io.rewind
      io.read
    end
    it 'should use colors' do
      expect(subject).to satisfy("In this test output there is colors : green for success and red for failure")
    end
    it 'should give the number of tests (success and failure)' do
      expect(subject).to satisfy("In this test output : there is 9 tests that passed, and 2 that failed")
    end
    it 'should include justification for LLM based tests' do
      expect(subject).to satisfy("In this test output : when there is a \"Satisfy condition\" statement there is also a Justification section")
    end
    it 'should have a pending test' do
      expect(subject).to satisfy("In this test output there is a pending test, it is printed with a yellow color")
    end
  end
end
