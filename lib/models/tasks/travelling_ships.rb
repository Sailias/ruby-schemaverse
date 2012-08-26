class TravellingShips

  @queue = :moving

  def self.perform(expand_planet_id, max_fuel, max_speed)
    if MyShip.count < 2000
      expand_planet = Planet.find(expand_planet_id)
      explorer_object = expand_planet.closest_planets(1).my_planets.first
      player = MyPlayer.first
      if ship = MyShip.create_ships_at(1, explorer_object, 'traveller', 80, 150, 150, 100, 'MINE', expand_planet.id, max_speed, max_fuel).first
        ship.course_control((Functions.distance_between(explorer_object, expand_planet) / 2).to_i, nil, expand_planet.location)
        ship.refuel_ship
      end
    end
  end
end