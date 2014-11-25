class News
  attr_accessor :id, :title, :url, :user_id, :ctime, :score, :rank, :up, :down,
                :comments, :category_id, :del, :type
  attr_writer :user_email
  attr_accessor :voted

  def initialize attrs={}
    attrs.each do |key, value|
      if %w(id user_id category_id ctime).include? key
        value = value.to_i
      elsif %w(ctime rank score).include? key
        value = value.to_f
      end
      send("#{key}=", value)
    end
  end

  # Return the host part of the news URL field.
  # If the url is in the form text:// nil is returned.
  def domain
    textual? ? nil : url.split("/")[2]
  end

  # Assuming the news has an url in the form text:// returns the text
  # inside. Otherwise nil is returned.
  def text
    textual? ? url[7..-1] : nil
  end

  def media_type
    unless textual?
      url_ext = url.split('.')[-1]
      return :image if url.downcase =~ /\.(jpg|jpeg|gif|png|tiff|bmp|svg)$/
      return :video if url =~ /(youtube|vimeo)/
    end
    nil
  end

  def to_h
    {
      "id" => id,
      "title" => title,
      "url" => url,
      "user_id" => user_id,
      "ctime" => ctime,
      "score" => score,
      "rank" => rank,
      "up" => up,
      "down" => down,
      "comments" => comments,
      "category_id" => category_id,
      "del" => del,
      "user_email" => user_email,
      "voted" => voted,
      "type" => media_type
    }
  end

  def user_email
    @user_email ||= User.find_email_by_id(user_id)
  end

  def textual?
    url =~ /^text\:\/\//
  end

  def update new_title, new_url
    if new_url != url
      $r.del "url:#{url}"
      self.url = new_url
      $r.setex "url:#{new_url}", PreventRepostTime, id unless textual?
    end
    self.title = new_title
    $r.hmset "news:#{id}", "title", title, "url", url
    true
  end

  def destroy
    $r.hmset "news:#{id}", "del", 1
    $r.zrem "news.top", id
    $r.zrem "news.cron", id
    if category_id
      $r.zrem "news.top.by_category:#{category_id}", id
      $r.zrem "news.cron.by_category:#{category_id}", id
    end
    true
  end

  def voted_by? user_id
    $r.zscore("news.up:#{id}", user_id) || $r.zscore("news.down:#{id}", user_id)
  end

  def vote user, vote_type
    return false, "Duplicated vote." if voted_by? user.id
    if user.id != user_id && !user.enough_karma_to_vote?(vote_type)
      return false, "You don't have enough karma to vote #{vote_type}"
    end
    # News was not already voted by that user. Add the vote.
    # Note that even if there is a race condition here and the user may be
    # voting from another device/API in the time between the ZSCORE check
    # and the zadd, this will not result in inconsistencies as we will just
    # update the vote time with ZADD.
    if $r.zadd "news.#{vote_type}:#{id}", Time.now.to_i, user.id
      $r.hincrby "news:#{id}", vote_type, 1
    end
    $r.zadd "user.saved:#{user.id}", Time.now.to_i, id if vote_type == :up

    update_score_and_karma

    # Remove some karma to the user if needed, and transfer karma to the
    # news owner in the case of an upvote.
    transfer_karma user, vote_type if user.id != user_id

    return rank, nil
  end

  def self.find_id_by_url url
    id = $r.get "url:#{url}"
    id ? id.to_i : nil
  end

  def self.find ids, opts={}
    normalized_ids = [ids].flatten
    grouped_values = $r.pipelined do
      normalized_ids.each { |id| $r.hgetall "news:#{id}" }
    end
    news = grouped_values.select(&:any?).map { |values| new(values) }
    if opts[:update_rank]
      $r.pipelined { news.each &:update_rank_if_needed }
    end
    fill_users_in_collection(news)
    fill_voted_info_in_collection(news, opts[:user_id]) if opts[:user_id]
    ids.is_a?(Array) && news || news.first
  end

  def self.create title, url, user, category
    ctime = Time.new.to_i
    id = $r.incr "news.count"
    $r.hmset "news:#{id}",
      "id",          id,
      "title",       title,
      "url",         url,
      "user_id",     user.id,
      "ctime",       ctime,
      "score",       0,
      "rank",        0,
      "up",          0,
      "down",        0,
      "comments",    0,
      "category_id", (category ? category.id : nil)
    find(id).tap do |news|
      # The posting user virtually upvoted the news posting it
      rank, error = news.vote user, :up
      # Add the news to the user submitted news
      $r.zadd "user.posted:#{user.id}", ctime, id
      # Add the news into the chronological view
      $r.zadd "news.cron", ctime, id
      # Add the news into the top view
      $r.zadd "news.top", rank, id
      # Add the news url for some time to avoid reposts in short time
      $r.setex "url:#{url}", PreventRepostTime, id unless news.textual?

      if category
        $r.zadd "news.cron.by_category:#{category.id}", ctime, id
        $r.zadd "news.top.by_category:#{category.id}", rank, id
      end
    end
  end

  # Updating the rank would require some cron job and worker in theory as
  # it is time dependent and we don't want to do any sorting operation at
  # page view time. But instead what we do is to compute the rank from the
  # score and update it in the sorted set only if there is some sensible error.
  # This way ranks are updated incrementally and "live" at every page view
  # only for the news where this makes sense, that is, top news.
  #
  # Note: this function can be called in the context of redis.pipelined {...}
  def update_rank_if_needed
    real_rank = compute_rank
    delta_rank = (real_rank - rank).abs
    if delta_rank > 0.000001
      $r.hmset "news:#{id}", "rank", real_rank
      $r.zadd "news.top", real_rank, id
      $r.zadd "news.top.by_category:#{category_id}", real_rank, id if category_id
      self.rank = real_rank
    end
  end

  # Compute the new values of score and karma, updating the news accordingly.
  def update_score_and_karma
    self.score = compute_score
    self.rank = compute_rank
    $r.hmset "news:#{id}",
    "score", score,
    "rank", rank
    $r.zadd "news.top", rank, id
    $r.zadd "news.top.by_category:#{category_id}", rank, id if category_id
  end

  def transfer_karma user, vote_type
    if vote_type == :up
      user.change_karma_by -NewsUpvoteKarmaCost
      User.change_karma_by user_id, NewsUpvoteKarmaTransfered
    else
      user.change_karma_by -NewsDownvoteKarmaCost
    end
  end

  private

  def compute_score
    upvotes = $r.zrange "news.up:#{id}", 0, -1, withscores: true
    downvotes = $r.zrange "news.down:#{id}", 0, -1, withscores: true
    # FIXME: For now we are doing a naive sum of votes, without time-based
    # filtering, nor IP filtering.
    # We could use just ZCARD here of course, but I'm using ZRANGE already
    # since this is what is needed in the long term for vote analysis.
    score = upvotes.length - downvotes.length
    # Now let's add the logarithm of the sum of all the votes, since
    # something with 5 up and 5 down is less interesting than something
    # with 50 up and 50 donw.
    votes = upvotes.length / 2 + downvotes.length / 2
    if votes > NewsScoreLogStart
      score += Math.log(votes - NewsScoreLogStart) * NewsScoreLogBooster
    end
    score
  end

  # Given the news compute its rank, that is function of time and score.
  #
  # The general forumla is RANK = SCORE / (AGE ^ AGING_FACTOR)
  def compute_rank
    age =  Time.now.to_i - ctime
    rank = (score * 1000000) / ((age + NewsAgePadding) ** RankAgingFactor)
    rank = - age if age > TopNewsAgeLimit
    rank
  end

  def self.fill_users_in_collection collection
    usernames = $r.pipelined do
      collection.each { |n| User.find_email_by_id n.user_id }
    end
    collection.each_with_index do |n, i|
      n.user_email = usernames[i]
    end
  end

  def self.fill_voted_info_in_collection collection, user_id
    votes = $r.pipelined do
      collection.each do |n|
        $r.zscore("news.up:#{n.id}", user_id)
        $r.zscore("news.down:#{n.id}", user_id)
      end
    end
    collection.each_with_index do |n,i|
      if votes[i*2]
        n.voted = :up
      elsif votes[(i*2)+1]
        n.voted = :down
      end
    end
  end
end
