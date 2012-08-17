class ArmadaShips
  @queue = :moving

  def self.perform(start_planet_id, objective_planet_id, num)

    closest_planet_to_objective = Planet.find start_planet_id
    planet_to_conquer = Planet.find objective_planet_id

    cost_of_attack_fleet = ((PriceList.ship) +
      (PriceList.defense * 200) +
      (PriceList.attack * 200) +
      (PriceList.prospecting * 20) +
      (PriceList.engineering * 80) +
      (Functions.get_numeric_variable('MAX_SHIP_FUEL') / 3) +
      (Functions.get_numeric_variable('MAX_SHIP_SPEED') / 3)
    ) * num

    MyPlayer.first.convert_fuel_to_money(cost_of_attack_fleet.to_i) if MyPlayer.first.balance < cost_of_attack_fleet
    num.times do
      begin
        armada_ship = MyShip.create(
          :name => "#{USERNAME}-armada",
          :prospecting => 5,
          :attack => 5,
          :defense => 5,
          :engineering => 5,
          :location => closest_planet_to_objective.location
        )

        if armada_ship.id?
          puts "New ARMADA SHIP"
          armada_ship = armada_ship.reload
          armada_ship.update_attributes(:action => "MINE", :action_target_id => planet_to_conquer.id)
          MyShip.
            select("UPGRADE(id, 'ATTACK', 200), UPGRADE(id, 'DEFENSE', 200), UPGRADE(id, 'MAX_SHIP_FUEL', #{(Functions.get_numeric_variable('MAX_SHIP_FUEL') / 3).to_i}), UPGRADE(id, 'MAX_SHIP_SPEED', #{(Functions.get_numeric_variable('MAX_SHIP_SPEED') / 3).to_i})").
            where(:id => armada_ship.id).first
          #armada_ship.upgrade("ATTACK", 200)
          #armada_ship.upgrade("DEFENSE", 200)
          #armada_ship.upgrade("MAX_FUEL", (Functions.get_numeric_variable('MAX_SHIP_FUEL') / 3).to_i)
          #armada_ship.upgrade("MAX_SPEED", (Functions.get_numeric_variable('MAX_SHIP_SPEED') / 3).to_i)

          if armada_ship.course_control((Functions.distance_between(armada_ship, planet_to_conquer) / 2).to_i, nil, planet_to_conquer.location)
            armada_ship.objective = planet_to_conquer
          end
        end
      rescue Exception => e
        puts e.message
        puts e.backtrace
      end
    end
  end
end