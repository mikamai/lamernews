class Category
  attr_accessor :id, :code

  def initialize attrs={}
    attrs.each do |key, value|
      value = value.to_i if %w(id).include? key
      send("#{key}=", value)
    end
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
