class TradeItem < ActiveRecord::Base
  self.primary_key = 'id'
  #belongs_to :my_trade, :foreign_key => "trade_id"


  def self.trade_ship(ship)
    ActiveRecord::Base.connection.execute("INSERT INTO trade_items (trade_id, player_id, description_code, quantity, descriptor) VALUES(#{MyTrade.first.id}, #{MyPlayer.first.id}, 'SHIP', 1, #{ship.id})")
    return TradeItem.last
  end

  def self.trade_ships(ships)
    success = true
    begin
      ship_ids = ships.collect(&:id).join(",")
      MyShip.where(:id => ship_ids).update_all("action=null", "1=1")
      ActiveRecord::Base.connection.execute("INSERT INTO trade_items (trade_id, player_id, description_code, quantity, descriptor) SELECT #{MyTrade.first.id}, #{MyPlayer.first.id}, 'SHIP', 1, my_ships.id FROM my_ships WHERE id IN (#{ship_ids})")
        #return TradeItem.last(ships.size)
    rescue
      success = false
    end
    return success
  end

  def self.trade_number_of_ships(n)
    success = true
    begin
      ActiveRecord::Base.connection.execute("INSERT INTO trade_items (trade_id, player_id, description_code, quantity, descriptor) SELECT #{MyTrade.first.id}, #{MyPlayer.first.id}, 'SHIP', 1, my_ships.id FROM my_ships WHERE name NOT LIKE '%traveller%' LIMIT #{n}") if n > 0
    rescue
      success = false
    end
    return success
  end

  def self.delete_trades(ship_ids)
    begin
      ActiveRecord::Base.connection.execute("DELETE FROM trade_items WHERE descriptor::integer IN (#{ship_ids.join(",")})")
        #MyShip.where(:id => ship_ids).update_all("action='MINE'", "1=1")
    rescue
    end
  end

  def self.destroy_all_trades
    val = true
    begin
      #ids = TradeItem.all.collect(&:descriptor)
      (TradeItem.count / 1000.0).ceil.times do
        ActiveRecord::Base.connection.execute("DELETE FROM trade_items WHERE id IN(SELECT id FROM trade_items LIMIT 1000)")
      end
        #ActiveRecord::Base.connection.execute("DELETE FROM trade_items")
        #MyShip.where(:id => ids).update_all("action='MINE'", "1=1")
    rescue
      val = false
    end
    return val
  end
end