class Schemaverse
  def initialize
    if Planet.where(:name => Planet.my_home_name).empty?
      new_home = Planet.my_planets.first
      new_home.update_attribute('name', Planet.my_home_name) if new_home
    end

    @my_player = MyPlayer.first
    @home = Planet.home
    @max_ship_skill = Functions.get_numeric_variable('MAX_SHIP_SKILL')
    @max_ship_fuel = Functions.get_numeric_variable('MAX_SHIP_FUEL')
    @ships = []
    @lost_ships = []
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

        my_planets = []
        my_planets = Planet.my_planets.order("planets.location<->POINT('#{@home.location}') DESC").all if @home
        new_planets = my_planets - @planets
        @lost_planets += @planets - my_planets
        @planets = my_planets

        my_ships = MyShip.all
        @lost_ships += @ships - my_ships
        @ships = my_ships

        @ships.each do |ship|
          # Loop through all ships to update their values in memory
          unless ship.objective.blank?
            # Update the location and the distance between the objective
            ship.distance_to_objective = Functions.distance_between(ship.location, objective.location)
          end
        end

        # Start killing of ships at planets that in my interior
        @planets.each do |planet|
          if planet.closest_planets(5).select { |p| p.conqueror_id != @my_player.id }.empty?
            planet.ships.each do |ship|
              # Have all the ships at the planet destroy themselves.
              # TODO, just put these ships into trade!
              ship.commence_attack(ship.id)
            end
          end
        end

        @planets.each do |planet|
          begin
            conquer_planet(planet)
          rescue Exception => e
            # Row locking was occurring on mass upgrading
            puts e.message
          end
        end

        # Ships that are out of fuel that haven't reached their destination
        puts "Checking for ships travelling that are out of fuel"
        @ships.select { |s| s.type.eql?("Travelling") }.each do |ship|
          if @my_player.fuel_reserve > ship.max_fuel
            ship.refuel_ship
            @my_player.fuel_reserve -= ship.max_fuel
          end
        end

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
      planet_in_array.closest_planets(5).where("conqueror_id <> ?", @my_player.id).each do |expand_planet|
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
              if explorer_ship.course_control(Functions.distance_between(explorer_object, planet) / 2, nil, planet.location)
                ship.type = "Travelling"
              end

              # Load the ship into our array
              @ships << ship
            end
          elsif explorer_object.is_a?(Ship) && explorer_object.type == "Travelling"
            explorer_object.queue += expand_planet
          end
        end
      end
    end
  end

  def calculate_efficient_travel(to)
    # first calculate if a new ship were to go there
    closest_planet = @planets.sort { |p| Functions.distance_between(p, to) }.first

    # calculate the closest travelling ship and it's distance to it's target and the distance
    # from the target to our target destination
    closest_travelling_ship = @ships.select{|s| s.type.eql?("Travelling")}.sort { |ts|
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
      @ships.select { |s| s.type.eql?("Travelling") }.inject(0) do |result, ship|
        # Keep the fuel above 50% at all times
        if ship.current_fuel < (ship.max_fuel / 2)
          result += ship.max_fuel - ship.current_fuel
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