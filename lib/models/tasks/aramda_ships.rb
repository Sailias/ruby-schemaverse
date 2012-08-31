class ArmadaShips
  @queue = :moving

  def self.perform(start_planet_id, objective_planet_id, num)

    if MyShip.count < (2000 - num)

      closest_planet_to_objective = Planet.find start_planet_id
      planet_to_conquer = Planet.find objective_planet_id
      player = MyPlayer.first
      max_fuel = (Functions.get_numeric_variable('MAX_SHIP_FUEL') / 3).to_i
      max_speed = (Functions.get_numeric_variable('MAX_SHIP_SPEED') / 3).to_i

      prospecting, attack, defense, engineering = 400, 40, 40, 0

      total_cost = ((PriceList.ship) +
        (PriceList.defense * defense) +
        (PriceList.attack * attack) +
        (PriceList.prospecting * prospecting) +
        (PriceList.engineering * engineering) +
        max_fuel +
        max_speed
      ) * num

      player.convert_fuel_to_money(total_cost - player.balance) if player.balance < total_cost
      if ships = MyShip.create_ships_at(num, closest_planet_to_objective, 'armada', prospecting, defense, attack, engineering, 'MINE', planet_to_conquer.id, max_speed, max_fuel, 0, [5, 5, 5, 5])
        ships.each do |ship|
          ship.course_control((Functions.distance_between(planet_to_conquer, closest_planet_to_objective) / 2).to_i, nil, planet_to_conquer.location)
        end
      end
    end
  end
end