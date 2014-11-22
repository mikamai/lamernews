require 'spec_helper'

describe 'urls_to_links' do
  [
    { :input => 'http://example.com',  :href => 'http://example.com',     :text => 'http://example.com' },
    { :input => 'http://example.com.', :href => 'http://example.com',     :text => 'http://example.com' },
    { :input => 'https://example.com', :href => 'https://example.com',    :text => 'https://example.com' },
    { :input => 'www.example.com',     :href => 'http://www.example.com', :text => 'www.example.com' },
    { :input => 'www.example.com.',    :href => 'http://www.example.com', :text => 'www.example.com' }
  ].each do |test_case|
    it "converts '#{test_case[:input]}' to HTML link to #{test_case[:href]}" do
      expected_link = "<a rel=\"nofollow\" href=\"#{test_case[:href]}\">#{test_case[:text]}</a>"
      expect(urls_to_links(test_case[:input])).to match(expected_link)
    end
  end
end

describe 'Lamer News' do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  describe '/' do
    context 'when I am not logged' do
      it 'contains a link with a login statement' do
        get '/'
        expect(last_response.body).to match /\<a.+\>login with google\<\/a\>/
      end

      it 'contains a link pointing to google oauth2 login' do
        get '/'
        expect(last_response.body).to match /\<a href\=\"\/auth\/google_oauth2\".+\>.*\<\/a\>/
      end
    end
  end

  describe '/auth/:provider/callback' do
    it 'returns a 404 if provider is not valid' do
      get '/auth/asd/callback'
      expect(last_response.status).to eq 404
    end

    it 'returns a 302 if request does not contain auth data' do
      get '/auth/google_oauth2/callback'
      expect(last_response.status).to eq 302
    end
  end

  describe '/api/create_account' do
    ['anti rez', '0antirez', '_antirez'].each do |invalid_username|
      context "with #{invalid_username} as username" do
        before do
          post '/api/create_account', {'username' => invalid_username, 'password' => 'valid password'}
        end

        it 'returns "Username must match" error' do
          expect(last_response).to be_ok
          expect(JSON.parse(last_response.body)['status']).to eq('err')
          expect(JSON.parse(last_response.body)['error']).to match(/Username must match/)
        end
      end
    end

    ['antirez', 'Antirez', 'antirez0', 'anti_rez', 'anti-rez'].each do |valid_username|
      context "with #{valid_username} as username" do
        before do
          post '/api/create_account', {'username' => valid_username, 'password' => 'valid password'}
        end

        it 'doesn\'t return "Username must match" error' do
          expect(last_response).to be_ok
          expect(JSON.parse(last_response.body)['error']).to_not match(/Username must match/)
        end
      end
    end
  end
end
