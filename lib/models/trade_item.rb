class TradeItem < ActiveRecord::Base
  self.primary_key = 'id'
  #belongs_to :my_trade, :foreign_key => "trade_id"


  def self.trade_ship(ship)
    ActiveRecord::Base.connection.execute("INSERT INTO trade_items (trade_id, player_id, description_code, quantity, descriptor) VALUES(#{MyTrade.first.id}, #{MyPlayer.first.id}, 'SHIP', 1, #{ship.id})")
    return TradeItem.last
  end

  def self.trade_ships(ships)
    begin
      ship_ids = ships.collect(&:id).join(",")
      MyShip.where(:id => ship_ids).update_all("action=null", "1=1")
      ActiveRecord::Base.connection.execute("INSERT INTO trade_items (trade_id, player_id, description_code, quantity, descriptor) SELECT #{MyTrade.first.id}, #{MyPlayer.first.id}, 'SHIP', 1, my_ships.id FROM my_ships WHERE id IN (#{ship_ids})")
      return TradeItem.last(ships.size)
    rescue
    end
  end

  def self.delete_trades(ship_ids)
    begin
      ActiveRecord::Base.connection.execute("DELETE FROM trade_items WHERE descriptor::integer IN (#{ship_ids.join(",")})")
      MyShip.where(:id => ship_ids).update_all("action='MINE'", "1=1")
    rescue
    end
  end
end