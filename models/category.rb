class Category
  attr_accessor :id, :code

  def initialize attrs={}
    attrs.each do |key, value|
      value = value.to_i if %w(id).include? key
      send("#{key}=", value)
    end
  end

  def top_news start=0, count=TopNewsPerPage
    numitems = $r.zcard("news.top.by_category:#{id}")
    news_ids = $r.zrevrange("news.top.by_category:#{id}",start,start+(count-1))
    result = News.find news_ids, update_rank: true
    # Sort by rank before returning, since we adjusted ranks during iteration.
    return result.sort_by(&:rank), numitems
  end

  def self.find_by_code code
    id = $r.get "category_codes.to.id:#{code}"
    id ? find(id) : nil
  end

  def self.find id
    values = $r.hgetall "category:#{id}"
    values.any? ? new(values) : nil
  end

  def self.create code
    id = $r.incr "categories.count"
    $r.hmset "category:#{id}",
      "id",   id,
      "code", code
    $r.set "category_codes.to.id:#{code}", id
    new
  end
end
