require 'spec_helper'

describe News do
  describe '#domain' do
    it 'returns nil when subject is textual' do
      subject = News.new url: 'text://asdasdasd'
      expect(subject.domain).to be_nil
    end

    it 'returns the domain part when subject is not textual' do
      subject = News.new url: 'http://www.google.com'
      expect(subject.domain).to eq 'www.google.com'
    end
  end

  describe '#text' do
    it 'returns nil when subject is not textual' do
      subject = News.new url: 'http://www.google.com'
      expect(subject.text).to be_nil
    end

    it 'returns text when subject is textual' do
      subject = News.new url: 'text://foobarbaz'
      expect(subject.text).to eq 'foobarbaz'
    end
  end

  describe '#user_email' do
    it 'is memoized' do
      subject = News.new
      subject.user_email = 'asd'
      expect(subject.user_email).to eq 'asd'
    end

    context 'when is not set' do
      it 'fetches the user email paired with the user_id set in the subject' do
        subject = News.new user_id: 'asd'
        expect(User).to receive(:find_email_by_id).with('asd')
        subject.user_email
      end

      it 'returns the fetched user email' do
        subject = News.new
        allow(User).to receive(:find_email_by_id).and_return 'asd'
        expect(subject.user_email).to eq 'asd'
      end
    end
  end

  describe '#textual?' do
    it 'returns true if news is textual' do
      subject = News.new url: 'text://asd'
      expect(subject).to be_textual
    end

    it 'returns false if news is an url' do
      subject = News.new url: 'http://www.google.com'
      expect(subject).to_not be_textual
    end
  end

  describe '#update' do
    let!(:user) { User.find_or_create 'a', 'a@a.it' }
    subject { News.create 'asd', 'http://foo.bar', user, nil }

    context 'when a new url is given' do
      it 'the new url is set in the subject' do
        expect { subject.update 'asd', 'http://bar.baz' }.to change(subject, :url).to 'http://bar.baz'
      end

      it 'removes the old url expiration key' do
        subject.update 'asd', 'http://bar.baz'
        expect($r.exists "url:http://foo.bar").to be_falsey
      end

      context 'and the new url is not textual' do
        it 'sets an expiration value to prevent repost' do
          subject # memoized
          expect($r).to receive(:setex).with("url:http://bar.baz", PreventRepostTime, 1)
          subject.update 'asd', 'http://bar.baz'
        end
      end

      context 'and the new url is textual' do
        it 'does not set an expiration value' do
          subject #memoized
          expect($r).to_not receive(:setex)
          subject.update 'asd', 'text://foobar'
        end
      end
    end

    context 'when the url is not changed' do
      it 'does not remove old url expiration key' do
        expect($r).to_not receive(:del).with("url:#{subject.url}")
        subject.update 'asd', subject.url
      end
    end

    it 'updates instance title' do
      expect { subject.update 'foo', subject.url }.to change(subject, :title).to 'foo'
    end

    it 'updates title on redis' do
      subject.update 'foo', subject.url
      expect($r.hget "news:#{subject.id}", "title").to eq "foo"
    end

    it 'updates url on redis' do
      subject.update 'asd', 'http://bar.baz'
      expect($r.hget "news:#{subject.id}", "url").to eq "http://bar.baz"
    end
  end

  describe '#destroy' do
    let!(:user) { User.find_or_create 'a', 'a@a.it' }
    let!(:category) { Category.create 'mikamai' }
    subject { News.create 'asd', 'http://foo.bar', user, category }

    it "sets the del attribute on redis" do
      subject.destroy
      expect($r.hget "news:#{subject.id}", "del").to eq "1"
    end

    it "removes the news from main top listing" do
      subject.destroy
      expect($r.zrevrange "news.top", 0, -1).to_not include subject.id.to_s
    end

    it "removes the news from main cron listing" do
      subject.destroy
      expect($r.zrevrange "news.cron", 0, -1).to_not include subject.id.to_s
    end

    context 'if news is in a category' do
      it "removes the news from category top listing" do
        subject.destroy
        listing = $r.zrevrange "news.top.by_category:#{subject.category_id}", 0, -1
        expect(listing).to_not include subject.id.to_s
      end

      it 'removes the news from category cron listing' do
        subject.destroy
        listing = $r.zrevrange "news.cron.by_category:#{subject.category_id}", 0, -1
        expect(listing).to_not include subject.id.to_s
      end
    end

    context 'if news is not in a category' do
      before { subject.category_id = nil }

      it 'does not alter category top listing' do
        subject.destroy
        listing = $r.zrevrange "news.top.by_category:#{category.id}", 0, -1
        expect(listing).to include subject.id.to_s
      end

      it 'does not alter category cron listing' do
        subject.destroy
        listing = $r.zrevrange "news.cron.by_category:#{category.id}", 0, -1
        expect(listing).to include subject.id.to_s
      end
    end
  end

  describe '#voted_by' do
    let!(:user) { User.find_or_create 'a', 'a@a.it' }
    subject { News.create 'asd', 'http://foo.bar', user, nil }

    it 'returns true if given user voted the subject up' do
      new_user_id = user.id + 1
      $r.zadd "news.up:#{subject.id}", 1, new_user_id
      expect(subject).to be_voted_by new_user_id
    end

    it 'returns true if given user voted the subject down' do
      new_user_id = user.id + 1
      $r.zadd "news.down:#{subject.id}", 1, new_user_id
      expect(subject).to be_voted_by new_user_id
    end

    it 'returns false if given user did not vote the subject' do
      expect(subject).to_not be_voted_by user.id + 1
    end
  end

  describe '#vote' do
    let!(:author) { User.find_or_create 'a', 'a@a.it' }
    subject { News.create 'asd', 'http://foo.bar', author, nil }
    let!(:user) { User.find_or_create 'foo', 'foo@bar.baz' }

    context 'when the user already voted the subject' do
      before do
        allow(user).to receive(:enough_karma_to_vote?).and_return true
        subject.vote user, :up
      end

      it 'returns false with a message' do
        expect(subject.vote user, :down).to eq [false, "Duplicated vote."]
      end
    end

    context 'when the user is not the author and it has not enough karma to vote' do
      before do
        expect(user).to receive(:enough_karma_to_vote?).with(:down).and_return false
      end

      it 'returns false with a message' do
        expect(subject.vote user, :down).to eq [false, "You don't have enough karma to vote down"]
      end
    end

    it 'adds the user_id to the votes collection' do
      subject.vote user, :down
      expect($r.zrevrange("news.down:#{subject.id}", 0, -1)).to include user.id.to_s
    end

    it 'adds the user_id to the votes collection with the actual time as score' do
      Timecop.freeze do
        subject.vote user, :down
        expect($r.zscore "news.down:#{subject.id}", user.id).to eq Time.now.to_i
      end
    end

    it 'increment the received votes' do
      subject.vote user, :down
      expect($r.hget "news:#{subject.id}", "down").to eq '1'
    end

    context 'when for some reason the user was in the votes collection' do
      before { $r.zadd "news.down:#{subject.id}", 1, user.id }

      it 'does not alter the received votes' do
        subject.vote user, :down
        expect($r.hget "news:#{subject.id}", "down").to eq '0'
      end
    end

    it 'updates score and karma' do
      expect(subject).to receive(:update_score_and_karma)
      subject.vote user, :down
    end

    it 'transfers karma when the user is not the author' do
      expect(subject).to receive(:transfer_karma).with(user, :down)
      subject.vote user, :down
    end

    it 'does not transfer karma when the user is the author' do
      expect(subject).to_not receive(:transfer_karma).with(user, :down)
      subject.vote author, :down
    end

    it 'returns the new rank' do
      expect(subject.vote user, :down).to eq [0.0, nil]
    end
  end

  describe '::find_id_by_url' do
    context 'when a pairing between url and id exist' do
      before { $r.set 'url:http://www.mikamai.com', '1' }

      it 'returns the id of the given url' do
        expect(News.find_id_by_url 'http://www.mikamai.com').to eq 1
      end
    end

    it 'returns nil when no pairing between given url and id exist' do
      expect(News.find_id_by_url 'http://www.mikamai.com').to be_nil
    end
  end

  describe '::find' do
    let!(:user) { User.find_or_create 'a', 'a@a.it' }
    before do
      2.times { News.create 'asd', 'text://asdasd', user, nil }
    end

    context 'when only one id is given' do
      it 'returns a single News when the id is found' do
        expect(News.find 1).to be_a News
      end

      it 'returns nil when the id is not found' do
        expect(News.find 12).to be_nil
      end
    end

    context 'when an array of ids is given' do
      it 'returns an array' do
        expect(News.find [1,2]).to be_a Array
      end

      it 'returns an array of the same length when all ids are found' do
        expect(News.find([1,2]).length).to eq 2
      end

      it 'returns an array of different length when one or more ids cannot be found' do
        expect(News.find([3,2]).length).to eq 1
      end
    end

    context 'when the update_rank option is given' do
      it 'calls #update_rank_if_needed on each returned news' do
        received_calls = 0
        allow_any_instance_of(News).to receive :update_rank_if_needed do
          received_calls += 1
        end
        News.find([1,2,3], update_rank: true)
        expect(received_calls).to eq 2
      end
    end

    context 'when the update_rank option is not given' do
      it 'does not call #update_rank_if_needed' do
        expect_any_instance_of(News).to_not receive(:update_rank_if_needed)
        News.find [1,2,3]
      end
    end

    it 'fills user emails in returned objects' do
      expect(News.find([1,2]).map(&:user_email).uniq).to eq [user.email]
    end

    context 'when the user_id option is given' do
      it 'fills voted info in returned objects' do
        expect(News.find([1,2], user_id: user.id).map(&:voted).uniq).to eq [:up]
      end
    end

    context 'when the user_id option is given' do
      it 'does not fill voted info in returned objects' do
        expect(News.find([1,2]).map(&:voted).uniq).to eq [nil]
      end
    end
  end

  describe '#media_type' do
    it 'returns nil when subject is textual' do
      subject.url = "text://asdasdasda.jpg"
      expect(subject.media_type).to be_nil
    end

    context 'returns image when' do
      %w(jpg jpeg png bmp tiff gif svg).each do |ext|
        it "url ends with .#{ext}" do
          subject.url = "http://asdasdasd.#{ext}"
          expect(subject.media_type).to eq :image
        end
      end
    end

    context 'returns video when' do
      %w(youtube|vimeo).each do |url|
        it "url contains #{url}" do
          subject.url = "http://asdad#{url}asdsd"
          expect(subject.media_type).to eq :video
        end
      end
    end
  end
end
