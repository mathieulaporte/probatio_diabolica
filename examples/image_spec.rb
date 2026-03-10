describe 'Image tests examples' do
  context 'with image analysis', model: "mistral-small-latest" do
    subject { File.open('examples/random_photo.png') }
    it 'should have a haystack' do
      expect.to satisfy('There is a haystack in the image.')
    end
    it 'should not have a cat' do
      expect.not_to satisfy('There is a cat in the image.')
    end
  end
end
