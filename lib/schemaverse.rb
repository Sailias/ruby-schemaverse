class Schemaverse
  def initialize
    if Planet.where(:name => Planet.my_home_name).empty?
      Planet.my_planets.first.update_attribute('name', Planet.my_home_name)
    end

    @my_player = MyPlayer.first
    @home = Planet.home
    @max_ship_skill = Functions.get_numeric_variable('MAX_SHIP_SKILL')
    @max_ship_fuel = Functions.get_numeric_variable('MAX_SHIP_FUEL')
    @ships = []
    @travelling_ships = []
    @planets = []
    @lost_planets = []
  end

  def play
    last_tic = 0

    while true
      # Adding cool names to my planets
      tic = TicSeq.first.last_value
      sleep(1)
      if last_tic != tic
        puts "Starting new Tic"
        last_tic = tic
        Planet.my_planets.not_home.where("name NOT LIKE ?", "%#{USERNAME}%").each_with_index do |planet, i|
          planet.update_attribute('name', Planet.get_new_planet_name(i.to_s))
        end

        my_planets = Planet.my_planets.order("planets.location<->POINT('#{@home.location}') DESC").all
        new_planets = my_planets - @planets
        @lost_planets += @planets - my_planets
        @planets = @planets + new_planets
        my_planets.each do |planet|
          begin
            conquer_planet(planet)
          rescue Exception => e
            # Row locking was occurring on mass upgrading
            puts e.message
          end
        end

        # Ships that are out of fuel that haven't reached their destination
        puts "Checking for ships travelling that are out of fuel"

        my_ships = MyShip.all
        @lost_ships += @ships - my_ships
        @ships = my_ships

        my_ships.each do |ship|
          # Loop through all ships to update their values in memory
          s = @ships[@ships.index(ship)]
          unless s.objective.blank?
            # Update the location and the distance between the objective
            s.location = ship.location
            s.distance_to_objective = Functions.distance_between(s.location, objective.location)
          end
        end


        #MyShip.where("not location ~= destination AND current_fuel < max_speed AND NOT CIRCLE(my_ships.destination, 10000) @> POINT(my_ships.location)").each do |explorer|
        #  begin
        #    puts "Refueling ship #{explorer.name}"
        #    explorer.refuel_ship
        #  rescue Exception => e
        #    puts e.message
        #  end
        #end

        puts "Checking for ships to attack"
        MyShip.joins(:ships_in_range).each do |attack_ship|
          begin
            attack_ship.commence_attack(attack_ship.ships_in_range.first.id)
          rescue Exception => e
            # Row locking was occurring on mass upgrading
            puts e.message
          end
        end
      end
    end
  end

  # @param [Object] planet
  def conquer_planet(planet)
    if planet.ships.size < planet.mine_limit && MyShip.count < 2001
      create_ships_for_planet(planet)
    else
      puts "#{planet.name} has maxed out on miners"
      upgrade_ships_at_planet(planet)
      expand_to_new_planet(planet)
    end
  end

  def create_ships_for_planet(planet)
    puts "This planet needs ships"
    (@my_player.balance / (PriceList.ship * PriceList.prospecting)).times do
      @my_player.convert_fuel_to_money(PriceList.ship) if @my_player.balance < PriceList.ship

      # If you can build another miner at this planet, do so
      ship = planet.ships.create(
        :name => "#{planet.name}-miner",
        :prospecting => 5,
        :attack => 5,
        :defense => 5,
        :engineering => 5,
        :location => planet.location
      )

      if ship.id?
        ship = ship.reload
        ship.update_attributes(:action => "MINE", :action_target_id => planet.id)
        # Load the ship into our array
        @ships << ship
      else
        # Break out of this loop if the ship could not be created
        break
      end

      puts "Created a ship for #{planet.name}"
      break if planet.ships.size >= 30
    end
  end

  def upgrade_ships_at_planet(planet)
    # If I have the same amount of miners on my home planet as the limit allows for, it makes more sense to upgrade the ships instead
    unless planet.ships.average("prospecting+engineering+defense+attack") == @max_ship_skill
      planet.ships.where("(prospecting+engineering+defense+attack) < ?", @max_ship_skill).each do |ship|
        begin
          skill_remaining = @max_ship_skill - ship.total_skill
          num_upgrades = @my_player.total_resources / PriceList.prospecting
          upgrade_amount = num_upgrades > skill_remaining ? skill_remaining : num_upgrades
          puts "upgrading ship skill by #{upgrade_amount}"

          if @planets.size > 25
            half_upgrade = upgrade_amount / 2
            @my_player.convert_fuel_to_money(half_upgrade * PriceList.prospecting) if @my_player.balance < (half_upgrade * PriceList.prospecting)
            ship.upgrade('PROSPECTING', half_upgrade)
            ship.update_attribute("name", "#{planet.name}-miner")

            @my_player.convert_fuel_to_money(half_upgrade * PriceList.attack) if @my_player.balance < (half_upgrade * PriceList.attack)
            ship.upgrade('ATTACK', half_upgrade)
            ship.update_attribute("name", "#{planet.name}-miner")
          else
            @my_player.convert_fuel_to_money(upgrade_amount * PriceList.prospecting) if @my_player.balance < (upgrade_amount * PriceList.prospecting)
            ship.upgrade('PROSPECTING', upgrade_amount)
            ship.update_attribute("name", "#{planet.name}-miner")
          end

        rescue Exception => e
          # Row locking was occurring on mass upgrading
          puts e.message
        end
      end
    end
  end

  def expand_to_new_planet(planet)
    # Our miners are getting maxed, lets build a ship and send him to the next closest planet

    planet_in_array = @planets[@planets.index(planet)]
    if planet_in_array
      planet_in_array.closest_planets(5).each do |expand_planet|
        unless @planets.include?(expand_planet)
          # This is still a planet we need to capture
          explorer_object = calculate_efficient_travel(to)
          if explorer_object.is_a?(Planet)
            ship = explorer_object.ships.create(
              :name => "#{USERNAME}-traveller",
              :prospecting => 5,
              :attack => 5,
              :defense => 5,
              :engineering => 5,
              :location => explorer_object.location
            )

            if ship.id?
              ship = ship.reload
              ship.update_attributes(:action => "ATTACK")
              # Load the ship into our array
              @ships << ship
              if explorer_ship.course_control(Functions.distance_between(explorer_object, planet) / 2, nil, planet.location)
                @travelling_ships << ship
              end
            end
          elsif explorer_object.is_a?(TravellingShip)
            TravellingShip.queue += explorer_object
          end
        end
      end

    end

    if MyShip.count < 2000 || planet.ships.count > 10
      finder = planet.closest_planets(2)
      MyShip.all.each do |my_ship|
        # Make sure we don't have any ships that have reached this planet but have not conquered it.
        finder = finder.where("NOT CIRCLE(planets.location, 10000) @> POINT(?)", my_ship.location)

        # Make sure we don't have any ships enroute to this planet
        finder = finder.where("NOT location ~= POINT(?)", my_ship.destination) unless my_ship.destination.blank?
      end
    else
      finder = []
    end
    finder.each do |closest_planet|
      if @my_player.total_resources >= 1000 + (total_cost = @max_ship_fuel * 2 + 360)
        explorer_ship = nil
        if MyShip.count < 2000
          @my_player.convert_fuel_to_money(1000) if @my_player.balance < 1000
          explorer_ship = planet.ships.create(
            :name => "#{USERNAME}-#{closest_planet.name}-explorer",
            :prospecting => 20,
            :attack => 0,
            :defense => 0,
            :engineering => 0,
            :location => planet.location
          )
        else
          explorer_ship = planet.ships.first
          explorer_ship.update_attribute("name", "#{USERNAME}-#{closest_planet.name}-explorer")
        end

        if explorer_ship && explorer_ship.id?
          puts "Expanding to the closest planet from #{planet.name} to #{closest_planet.name} which is #{closest_planet.distance} light years away"
          explorer_ship = explorer_ship.reload
          explorer_ship.update_attributes(:action => "MINE", :action_target_id => closest_planet.id)
          @my_player.convert_fuel_to_money((total_cost - @my_player.balance).ceil) if @my_player.balance < total_cost
          #upgrade_amount = closest_planet.distance.to_f.ceil > @max_ship_fuel - ship.max_fuel ? @max_ship_fuel - ship.max_fuel : closest_planet.distance.to_f.ceil
          explorer_ship.upgrade("MAX_FUEL", (@max_ship_fuel - explorer_ship.current_fuel).ceil) unless explorer_ship.current_fuel == @max_ship_fuel
          explorer_ship.upgrade("MAX_SPEED", (@max_ship_fuel / 2).to_i)
          explorer_ship.refuel_ship
          explorer_ship = explorer_ship.reload
          puts "Sending ship #{explorer_ship.name}"
          explorer_ship.course_control((closest_planet.distance.to_f / 2).ceil, nil, closest_planet.location)
        end
      end
    end
  end

  def calculate_efficient_travel(to)
    # first calculate if a new ship were to go there
    closest_planet = @planets.sort { |p| Functions.distance_between(p, to) }.first

    # calculate the closest travelling ship and it's distance to it's target and the distance
    # from the target to our target destination
    closest_travelling_ship = @travelling_ships.sort { |ts|
      (ts.distance_from_objective + Functions.distance_between(ts.objective, to)) / ts.max_speed
    }.first

    vals = {closest_planet => Functions.distance_between(closest_planet, to) / (PriceList.ship + available_income)} if @ships.size < 2000
    vals.merge!(closest_travelling_ship => Functions.distance_between(closest_ship.objective, to) / (PriceList.ship + available_income)) if closest_travelling_ship

    unless vals.empty?
      # Return the object to send
      vals.sort_by { |name, tics| tics }.to_a.first[0]
    else
      return nil
    end

  end

  class << self
    def fuel_needed_for_next_tic
      @ships.select { |s| !s.objective.blank? }.inject(0) do |result, ship|
        if ship.distance_to_objective < ship.max_fuel
          result += ship.distance_to_objective
        else
          result += ship.max_fuel
        end
      end
    end

    def estimated_income
      mining_gain_per_prospecting = 16.5
      @ships.select { |s| s.action == 'MINE' }.sum(&:prospecting) * mining_gain_per_prospecting
    end

    def total_expenses
      price_for_fuel = 1
      fuel_needed_for_next_tic * price_for_fuel
    end

    def available_income
      estimated_income - total_expenses
    end

  end

end