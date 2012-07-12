class PriceList < ActiveRecord::Base
  self.table_name = 'price_list'

  scope :with_code, lambda{|code|
    where(:code => code)
  }

  def self.method_missing(m)
    var = PriceList.with_code(m.to_s.upcase).first
    if var
      return var.cost
    else
      super
    end
  end
end