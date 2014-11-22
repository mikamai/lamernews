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
end
