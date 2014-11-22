require 'spec_helper'

describe Category do
  describe '::create' do
    it 'returns a Category' do
      expect(Category.create 'asd').to be_a Category
    end

    it 'generates a new id' do
      Category.create 'asd'
      expect($r.get "categories.count").to eq "1"
    end

    it 'stores code and id on redis' do
      Category.create 'asd'
      expect($r.hgetall "category:1").to eq "id" => "1", "code" => "asd"
    end

    it 'stores a pairing between code and id' do
      Category.create 'asd'
      expect($r.get 'category_codes.to.id:asd').to eq '1'
    end
  end

  describe '::find' do
    it 'returns nil if category with that id is not found' do
      expect(Category.find 1).to be_nil
    end

    it 'returns a category if exist with the given id' do
      Category.create 'mik'
      expect(Category.find 1).to be_a Category
    end

    it 'instantiates a category with all attributes found on redis' do
      Category.create 'mik'
      expect(Category).to receive(:new).with("id" => "1", "code" => "mik")
      Category.find(1)
    end
  end

  describe '::find_by_code' do
    it 'returns nil if category with that code does not exist' do
      expect(Category.find_by_code 'mik').to be_nil
    end

    it 'returns a category if a category with a given code exist' do
      Category.create 'mik'
      expect(Category.find_by_code 'mik').to be_a Category
    end

    it 'uses finds to fetch the category via the id if category exist' do
      Category.create 'mik'
      expect(Category).to receive(:find).with('1').and_return 'asd'
      expect(Category.find_by_code 'mik').to eq 'asd'
    end
  end
end
