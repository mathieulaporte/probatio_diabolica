describe 'Image tests examples' do
  context 'with image analysis', model: "mistralai/mistral-small-3.2-24b-instruct:free" do
    let(:image) { File.open('examples/random_photo.png') }
    it 'should have a haystack' do
      expect(image).to satisfy('There is a haystack in the image.')
    end
    it 'should not have a cat' do
      expect(image).not_to satisfy('There is a cat in the image.')
    end
  end
end 