class RefuelShips

  @queue = :refuel

  def self.perform(ship_ids)
    ships_to_refuel = MyShip.where(:id => ship_ids)
    MyShip.refuel_ships(ships_to_refuel)
  end

end