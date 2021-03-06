class User
  attr_accessor :id, :name, :salt, :password, :ctime, :karma, :about, :email,
                :auth, :apisecret, :flags, :karma_incr_time, :replies

  def initialize args={}
    args.each do |key, val|
      val = val.to_i if %w(id karma).include?(key)
      send "#{key}=", val
    end
  end

  def enough_karma_to_vote? vote_type
    return (vote_type == :up && karma < NewsUpvoteMinKarma) ||
           (vote_type == :down && karma < NewsDownvoteMinKarma)
  end

  def change_karma_by amount
    self.karma += amount
    $r.hincrby "user:#{id}", "karma", amount
    karma
  end

  def update_auth_token
    $r.del "auth:#{auth}"
    self.auth = self.class.generate_auth_token
    $r.hmset "user:#{id}", "auth", auth
    $r.set "auth:#{auth}", id
    auth
  end

  def update_about about
    self.about = about
    $r.hmset "user:#{id}", "about", about[0..4095]
  end

  def self.change_karma_by id, amount
    $r.hincrby "user:#{id}", "karma", amount
  end

  def self.find_email_by_id id
    $r.hget "user:#{id}", "email"
  end

  def self.find_or_create_using_google_oauth2 auth_data
    find_or_create auth_data['info']['name'], auth_data['info']['email']
  end

  def self.find_or_create name, email
    find_by_email(email) || create(name, email)
  end

  def self.create name, email
    id = $r.incr("users.count")
    auth_token = generate_auth_token
    apisecret = generate_api_secret
    $r.hmset "user:#{id}",
      "id",              id,
      "name",            name,
      "ctime",           Time.now.to_i,
      "karma",           UserInitialKarma,
      "about",           "",
      "email",           email,
      "auth",            auth_token,
      "apisecret",       apisecret,
      "flags",           "",
      "karma_incr_time", Time.now.to_i
    $r.set "email.to.id:#{email}", id
    $r.set "auth:#{auth_token}", id
    find(id)
  end

  def self.find_by_email email
    id = $r.get("email.to.id:#{email}")
    id && find(id) || nil
  end

  def self.find_by_auth_token auth
    id = $r.get("auth:#{auth}")
    id && find(id) || nil
  end

  def self.find id
    values = $r.hgetall("user:#{id}")
    new values if values.any?
  end

  def self.deleted_one
    @deleted_one ||= new
  end

  private

  def self.generate_auth_token
    get_rand
  end

  def self.generate_api_secret
    get_rand
  end
end
