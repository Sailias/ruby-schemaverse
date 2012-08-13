class MyTrade < ActiveRecord::Base
  self.primary_key = 'id'
  has_many :items, :class_name => "TradeItem", :foreign_key => "trade_id"


  def self.create_trade
    player = MyPlayer.first
    trade = MyTrade.first
    unless trade
      ActiveRecord::Base.connection.execute("INSERT INTO my_trades (player_id_1, player_id_2) VALUES(#{player.id}, #{player.trade_partner_id})")
      trade = MyTrade.first
    end
    return trade
  end
end