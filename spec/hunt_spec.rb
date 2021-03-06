require 'helper'
#encoding: utf-8

class Note
  include MongoMapper::Document

  plugin Hunt

  scope :by_user, lambda { |user| where(:user_id => user.id) }

  key :title,   String
  key :body,    String
  key :tags,    Array
  key :user_id, ObjectId

  belongs_to :user

end

class User
  include MongoMapper::Document
  many :notes
end

describe Hunt do
  it "adds searches key to model to store search terms" do
    Note.searches(:title)
    Note.new.should respond_to(:searches)
    Note.new.should respond_to(:searches=)
  end

  describe ".search" do
    before(:each) do
      Note.searches(:title)
    end

    it "returns query that matches nothing if nil" do
      Note.create(:title => 'Mongo')
      Note.search(nil).count.should == 0
    end

    it "returns query that matches nothing if blank" do
      Note.create(:title => 'Mongo')
      Note.search('').count.should == 0
    end


    context 'using .configure' do
      after(:all) do
        Hunt.configure do |config|
          config.transliteration_option = nil
        end
      end

      it 'returns a query result when black list was not updated' do
        Hunt.configure
        Note.create(:title => 'bang yabadabaduu')
        Note.search('bang').count.should == 1
        Note.search('yabadabaduu').count.should == 1
      end

      it 'should ommit words which was added to black list' do
        Hunt.configure do |config|
          config.additional_words_to_ignore = ["bang", 'yabadabaduu']
        end
        Note.create(:title => 'bang yabadabaduu')
        Note.search('bang').count.should == 0
        Note.search('yabadabaduu').count.should == 0
      end

      it "adds index key as symbol if it was defined" do
        searches_index_name = :"searches.default"
        Hunt.configure do |config|
          config.searches_index_name = searches_index_name
        end
        Hunt.searches_index_name.should == searches_index_name
      end

      it "adds index as array if it was defined" do
        searches_index_name = [[:"searches.default", Mongo::ASCENDING], [:user_dir, Mongo::ASCENDING]]
        Hunt.configure do |config|
          config.searches_index_name = searches_index_name
        end
        Hunt.searches_index_name.should == searches_index_name
      end

      it "should set transliteration_option if it was defined" do
        transliteration_option = :german
        Hunt.transliteration_option.should be_nil
        Hunt.configure do |config|
          config.transliteration_option = transliteration_option
        end
        Hunt.transliteration_option.should == transliteration_option
        Note.create(:title => data_samples["german"]['note_title'] )
        Note.search(data_samples["german"]['search_phrase']).count.should == 1
      end
    end

    context "chained on scope" do
      before(:each) do
        @user = User.create
        @note = Note.create(:title => 'Mongo', :user_id => @user.id)
      end

      it "works" do
        Note.by_user(@user).search('Mongo').all.should == [@note]
      end
    end

    context "chained on association" do
      before(:each) do
        @user = User.create
        @note = Note.create(:title => 'Mongo', :user_id => @user.id)
      end

      it "works" do
        @user.notes.search('Mongo').all.should == [@note]
        @user.notes.search('Frank').all.should == []
      end
    end

    context "with one search term" do
      before(:each) do
        @note   = Note.create(:title => 'MongoDB is awesome!')
        @result = Note.search('mongodb')
      end

      let(:note)    { @note }
      let(:result)  { @result }

      it "returns plucky query" do
        result.should be_instance_of(Plucky::Query)
      end

      it "scopes query to searches.default in stemmed terms" do
        result['searches.default'].should == {'$in' => %w(mongodb)}
      end

      it "does return matched documents" do
        result.all.should include(note)
      end

      it "does not query unmatched documents" do
        not_found = Note.create(:title => 'Something different')
        result.all.should_not include(not_found)
      end
    end

    context "with multiple search terms" do
      before(:each) do
        @note   = Note.create(:title => 'MongoDB is awesome!')
        @result = Note.search('mongodb is awesome')
      end

      let(:note)    { @note }
      let(:result)  { @result }

      it "returns plucky query" do
        result.should be_instance_of(Plucky::Query)
      end

      it "scopes query to searches.default in stemmed terms" do
        result['searches.default'].should == {'$in' => Hunt::Util.to_stemmed_words(note.concatted_search_values)}
      end

      it "returns documents that match both terms" do
        result.all.should include(note)
      end

      it "returns documents that match any of the terms" do
        awesome = Note.create(:title => 'Something awesome')
        mongodb = Note.create(:title => 'Something MongoDB')
        result.all.should include(awesome)
        result.all.should include(mongodb)
      end

      it "does not query unmatched documents" do
        not_found = Note.create(:title => 'Something different')
        result.all.should_not include(not_found)
      end
    end
  end

  context "Search indexing" do
    context "on one field" do
      before(:each) do
        Note.searches(:title)
        @note = Note.create(:title => 'Woot for MongoDB!')
      end

      let(:note) { @note }

      it "indexes terms on create" do
        note.searches['default'].should == Hunt::Util.to_stemmed_words(note.concatted_search_values)
      end

      it "indexes terms on update" do
        note.update_attributes(:title => 'Another woot')
        note.searches['default'].should == Hunt::Util.to_stemmed_words(note.concatted_search_values)
      end
    end

    context "on multiple fields" do
      before(:each) do
        Note.searches(:title, :body)
        @note = Note.create(:title => 'Woot for MongoDB!', :body => 'This is my body.')
      end

      let(:note) { @note }

      it "indexes merged terms on create" do
        note.searches['default'].should == Hunt::Util.to_stemmed_words(note.concatted_search_values)
      end

      it "indexes merged terms on update" do
        note.update_attributes(:title => 'Another woot', :body => 'An updated body.')
        note.searches['default'].should == Hunt::Util.to_stemmed_words(note.concatted_search_values)
      end
    end

    context "on multiple fields one of which is array key" do
      before(:each) do
        Note.searches(:title, :tags)
        @note = Note.create(:title => 'Woot for MongoDB!', :tags => %w(mongo nosql))
      end

      let(:note) { @note }

      it "indexes merged terms on create" do
        note.searches['default'].should == Hunt::Util.to_stemmed_words(note.concatted_search_values)
      end

      it "indexes merged terms on update" do
        note.update_attributes(:title => 'Another woot', :tags => %w(mongo))
        note.searches['default'].should == Hunt::Util.to_stemmed_words(note.concatted_search_values)
      end
    end
  end
end
