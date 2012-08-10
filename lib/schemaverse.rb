class Schemaverse
  def initialize
    set_up_variables
  end

  def determine_home
    if Planet.where(:name => Planet.my_home_name).empty?
      new_home = Planet.my_planets.first
      new_home.update_attribute('name', Planet.my_home_name) if new_home
    end
    @home = Planet.home
  end

  def set_up_variables
    @my_player = MyPlayer.first
    determine_home
    @max_ship_skill = Functions.get_numeric_variable('MAX_SHIP_SKILL')
    @max_ship_fuel = Functions.get_numeric_variable('MAX_SHIP_FUEL')
    @ships = MyShip.all
    @travelling_ships = []
    @armada_ships = []

    @ships.select { |s| !s.destination.blank? }.each do |ship|
      ship.objective = Planet.where("location ~= POINT(?)", ship.destination).first
    end

    @travelling_ships = @ships.select{|s| s.objective && !s.name.include?("armada")}
    @armada_ships = @ships.select{|s| s.objective && s.name.include?("armada")}

    @lost_ships = []
    @my_planets = Planet.my_planets.all
    @planets = []
    @objective_planets = []
    @armada_planets = []
    @lost_planets = []
    @tic = 0
    
    
    @armada_ships.each do |ship|
      @armada_planets << ship.objective unless @armada_planets.include?(ship.objective)
    end

    Planet.not_my_planets.select("id, name, location, conqueror_id, planets.location<->POINT('#{@home.location}') as distance").order("distance ASC").each do |planet|
      #REDIS.rpush 'objective_planets', planet.attributes.to_json
      @objective_planets << planet
    end
  end

  def play
    last_tic = 0
    last_round = nil
    set_up_variables

    while true
      # Adding cool names to my planets
      @tic = TicSeq.first.last_value
      @round = RoundSeq.first.last_value
      last_round ||= @round

      unless last_round.eql?(@round)
        puts "A NEW ROUND HAS BEGUN!!"
        # RESET EVERYTHING

        # Destroy all but 30 ships if there are some already made
        puts "A new round has begun"
        (MyShip.all - MyShip.first(30)).each do |ship|
          ship.destroy
        end

        determine_home

        # Make all existing ships mine home
        MyShip.all.update_attribute("action_target_id", @home.id)
        set_up_variables
      end

      if last_tic != @tic
        #sleep(45) # Wait 45 seconds into each round for the data to propagate
        determine_home
        puts "Starting new Tic"
        last_tic = @tic

        @my_player = MyPlayer.first

        my_planets = []
        my_planets = Planet.my_planets.order("planets.location<->POINT('#{@home.location}') DESC").all if @home
        new_planets = my_planets - @planets

        new_planets.each_with_index do |planet, i|
          planet.update_attribute('name', Planet.get_new_planet_name(i.to_s))
          @objective_planets.delete(planet) if @objective_planets.index(planet)
        end

        @lost_planets += @planets - my_planets
        @planets = my_planets       

        @lost_planets.each do |lost_planet|
          @armada_planets.unshift(lost_planet) unless @armada_planets.include?(lost_planet)
        end

        @lost_planets = []

        my_ships = MyShip.all
        new_ships = my_ships - @ships
        @lost_ships += @ships - my_ships
        @ships = @ships - @lost_ships
        @travelling_ships = @travelling_ships - @lost_ships
        @armada_ships = @armada_ships - @lost_ships

        #@travelling_ships = []
        #my_ships.select { |s| !s.destination.blank? }.each do |ship|
        #  ship.objective = Planet.where("location ~= POINT(?)", ship.destination).first
        #  if ship.objective
        #    @travelling_ships << ship
        #  end
        #end

        # Add the planet back to the start of our objective planets
        @lost_ships.collect(&:objective).compact.select { |o| o.is_a?(Planet) && !@planets.include?(o) }.each do |planet|
          @objective_planets.shift(planet) unless @objective_planets.include?(planet) || @planets.include?(planet)
        end

        # Expand to new planets based on tic
        if @travelling_ships.size <= @tic / 3
          ((@tic / 3) - @travelling_ships.size).to_i.times do |i|
            expand_to_new_planet(@objective_planets[i])
          end
        end

        @planets.sort_by { |p| Functions.distance_between(p, @home) }.reverse.each do |planet|
          if (planet.mine_limit - planet.ships.size) > 0 && MyShip.count < 1400 && !planet.closest_planets(5).select { |p| p.conqueror_id != @my_player.id }.empty?
            puts "#{planet.name} needs ships"
            create_ships_for_planet(planet)
          else
            upgrade_ships_at_planet(planet)
          end
        end

        # Ships that are out of fuel that haven't reached their destination
        puts "Checking for ships travelling that are out of fuel"
        @travelling_ships.select { |s| !s.at_destination? && s.current_fuel < (s.max_fuel / 2) }.each do |ship|
          if @my_player.fuel_reserve > ship.max_fuel
            puts "Refueling #{ship.name}"
            ship.refuel_ship
            @my_player.fuel_reserve -= ship.max_fuel - ship.current_fuel
          end
        end

        puts "Checking for armada travelling that are out of fuel"
        @armada_ships.select { |s| !s.at_destination? && s.current_fuel < (s.max_fuel / 2) }.each do |ship|
          if @my_player.fuel_reserve > ship.max_fuel
            puts "Refueling #{ship.name}"
            ship.refuel_ship
            @my_player.fuel_reserve -= ship.max_fuel - ship.current_fuel
          end
        end

        # Start killing of ships at planets that in my interior
        @planets.sort_by { |p| Functions.distance_between(p, @home) }.each do |planet|
          #  conquer_planet(planet)
          #
          if planet.closest_planets(5).select { |p| p.conqueror_id != @my_player.id }.empty? && @ships.size >= 2000
            all_ships = planet.ships
            unless all_ships.empty?
              all_ships.each do |ship|
                puts "Killing #{ship.name}"
                # Have all the ships at the planet destroy themselves.
                # TODO, just put these ships into trade!
                begin
                  ship.destroy
                rescue Exception => e
                  puts e.message
                end
              end
            end
          else
            planet.closest_planets(5).select { |p| p.conqueror_id != @my_player.id }.each do |p|
              @armada_planets.unshift(p) unless @armada_planets.include?(p) && @objective_planets.include?(p)
            end
          end
        end

		puts "Number of armada groups: #{@armada_ships.group_by(&:objective).size}"
        if @armada_ships.group_by(&:objective).size < 20 && @ships.size <= 1970
          # Create another group of amada ships if you can
          cost_of_attack_fleet = ((PriceList.ship) +
            (PriceList.defense * 200) +
            (PriceList.attack * 200) +
            (Functions.get_numeric_variable('MAX_SHIP_FUEL') / 3) +
            (Functions.get_numeric_variable('MAX_SHIP_SPEED') / 3)
          ) * 30
          
          if @my_player.total_resources >= cost_of_attack_fleet
			
			@my_player.convert_fuel_to_money(cost_of_attack_fleet.to_i) if @my_player.balance < cost_of_attack_fleet
            planet_to_conquer = @armada_planets.first
            if planet_to_conquer
              closest_planet_to_objective = planet_to_conquer.closest_planets(1).my_planets.first
              30.times do
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
                  armada_ship.update_attributes(:action => "ATTACK")
                  armada_ship.upgrade("ATTACK", 200)
                  armada_ship.upgrade("DEFENSE", 200)
                  armada_ship.upgrade("MAX_FUEL", (Functions.get_numeric_variable('MAX_SHIP_FUEL') / 3).to_i)
                  armada_ship.upgrade("MAX_SPEED", (Functions.get_numeric_variable('MAX_SHIP_SPEED') / 3).to_i)
                  @my_player.balance -= cost_of_attack_fleet

                  if armada_ship.course_control((Functions.distance_between(armada_ship, planet_to_conquer) / 2).to_i, nil, planet_to_conquer.location)

                    armada_ship.objective = planet_to_conquer
                    @armada_ships << armada_ship
                    @armada_planets.delete(planet_to_conquer)
                  end

                  # Load the ship into our array
                  @ships << armada_ship
                end
              end
            end
          end
        end

        # handle all travelling ships
        @travelling_ships.sort_by(&:distance_from_objective).each do |travelling_ship|
          begin
			  if travelling_ship.at_destination?
				if travelling_ship.objective.is_a?(Planet)
				  if @planets.include?(travelling_ship.objective) || travelling_ship.ships_in_range.size > 0
					# Lets move this ship to another planet!
					new_planet = @objective_planets.sort_by { |p| Functions.distance_between(p, travelling_ship) }.first
					if travelling_ship.course_control(travelling_ship.max_speed, nil, new_planet.location)
					  travelling_ship.objective = new_planet
					  @objective_planets.delete(new_planet)
					end

					if travelling_ship.ships_in_range.size > 0
					  # lets do something here to capture this planet
					  # @armada_planets << travelling_ship.objective
					end

				  else
					puts "#{travelling_ship.name} is at the location. Mining#{travelling_ship.objective.name}"
					travelling_ship.update_attributes(:action => "MINE", :action_target_id => travelling_ship.objective.id)
				  end
				else
				  # Something else needs to happen here
				end
			  else
				begin
				  travelling_ship.modify_speed(@ships)
				  travelling_ship.modify_fuel(@ships)
				rescue Exception => e
				  puts e.message
				end
			  end

			  #if @planets.include?(travelling_ship.objective)
			  #  puts "Processing queue"
			  #  travelling_ship.process_next_queue_item
			  #end
          rescue Exception => e
			puts e.message
          end
        end

        @armada_ships.group_by(&:objective).each do |armada_ship_grp|
          if armada_ship_grp.last[0].at_destination?
            if armada_ship_grp.last[0].ships_in_range.empty? || armada_ship_grp.last[0].ships_in_range.select{|s| s.health > 0}.size.zero?
              armada_ship_grp.last.each do |armada_ship|
                armada_ship.update_attributes(:action => "MINE", :action_target_id => armada_ship.objective.id)
              end
            end

            if @planets.include?(armada_ship_grp.first)
              new_armada_planet = @armada_planets.sort_by { |p| Functions.distance_between(p, armada_ship_grp.first) }.first
              if new_armada_planet
                puts "MISSION COMPLETE!! MOVE ON"
                puts "moving ships to #{new_armada_planet.name}"
                armada_ship_grp.last.each do |armada_ship|
                  if armada_ship.course_control(armada_ship.max_speed, nil, new_armada_planet.location)
                    armada_ship.objective = new_armada_planet
                  end
                end
                @armada_planets.delete(new_armada_planet)
              end
            end
          end
        end

        puts "Checking for ships to attack"
        attacking_ships = []
        MyShip.joins(:ships_in_range).all.uniq.each do |s|
          attack_ship = s.ships_in_range.all.select{|s| !attacking_ships.include?(s)}.first
          unless attack_ship.nil?
			  attacking_ships << attack_ship
			  begin            
				s.commence_attack(attack_ship.id)
			  rescue Exception => e
				# Row locking was occurring on mass upgrading
				puts e.message
			  end
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
      upgrade_ships_at_planet(planet)
      expand_to_new_planet(planet)
    end
  end

  def create_ships_for_planet(planet)
    (planet.mine_limit - planet.ships.size).times do
      next if @my_player.total_resources < PriceList.ship
      if @my_player.balance < PriceList.ship
        @my_player.convert_fuel_to_money(PriceList.ship)
      end

      # If you can build another miner at this planet, do so
      ship = planet.ships.create(
        :name => "#{planet.name}-miner",
        :prospecting => 5,
        :attack => 5,
        :defense => 5,
        :engineering => 5,
        :location => planet.location
      )

      if ship.id
        @my_player.balance -= PriceList.ship
        ship = ship.reload
        begin
          ship.update_attributes(:action => "MINE", :action_target_id => planet.id)
        rescue Exception => e
          puts e.message
        end
        # Load the ship into our array
        @ships << ship
        puts "Created a ship for #{planet.name}"
      else
        # Break out of this loop if the ship could not be created
        puts "ERROR CREATING SHIP"
        break
      end
      break if planet.ships.size >= planet.mine_limit
    end
  end

  def upgrade_ships_at_planet(planet)
    # If I have the same amount of miners on my home planet as the limit allows for, it makes more sense to upgrade the ships instead
    unless planet.ships.average("prospecting+engineering+defense+attack") == @max_ship_skill
      planet.ships.where("(prospecting+engineering+defense+attack) < ?", @max_ship_skill).each do |ship|
        begin
          skill_remaining = @max_ship_skill - ship.total_skill
          num_upgrades = @my_player.total_resources / PriceList.prospecting
          upgrade_amount = num_upgrades > skill_remaining ? skill_remaining.to_i : num_upgrades.to_i
          if upgrade_amount > 0
            puts "upgrading ship skill by #{upgrade_amount}"
            if (@planets.size > 25 || @tic > 80) && upgrade_amount / 2 > 1
              half_upgrade = (upgrade_amount / 2).to_i
              @my_player.convert_fuel_to_money((half_upgrade * PriceList.prospecting).to_i) if @my_player.balance < (half_upgrade * PriceList.prospecting)
              ship.upgrade('PROSPECTING', half_upgrade)
              ship.update_attribute("name", "#{planet.name}-miner") unless ship.name.include?("armada") || ship.name.include?("traveller")
              @my_player.balance -= half_upgrade * PriceList.prospecting

              @my_player.convert_fuel_to_money((half_upgrade * PriceList.attack).to_i) if @my_player.balance < (half_upgrade * PriceList.attack)
              ship.upgrade('ATTACK', half_upgrade)
              ship.update_attribute("name", "#{planet.name}-miner") unless ship.name.include?("armada") || ship.name.include?("traveller")
              @my_player.balance -= half_upgrade * PriceList.attack
            else
              @my_player.convert_fuel_to_money((upgrade_amount * PriceList.prospecting).to_i) if @my_player.balance < (upgrade_amount * PriceList.prospecting)
              ship.upgrade('PROSPECTING', upgrade_amount)
              ship.update_attribute("name", "#{planet.name}-miner") unless ship.name.include?("armada") || ship.name.include?("traveller")
              @my_player.balance -= upgrade_amount * PriceList.prospecting
            end
          end

        rescue Exception => e
          # Row locking was occurring on mass upgrading
          puts e.message
        end
      end
    end
  end

  def expand_to_new_planet(expand_planet)
    # Our miners are getting maxed, lets build a ship and send him to the next closest planet
    #planet.closest_planets(10).where("conqueror_id <> ?", @my_player.id).select { |p| !@ships.collect(&:objective).include?(p) }.each do |expand_planet|
    #unless @planets.include?(expand_planet)
    # This is still a planet we need to capture
    explorer_object = calculate_efficient_travel(expand_planet)
    if explorer_object.is_a?(Planet)
      @my_player.convert_fuel_to_money(PriceList.ship) if @my_player.balance < PriceList.ship
      explorer_ship = explorer_object.ships.create(
        :name => "#{USERNAME}-traveller",
        :prospecting => 5,
        :attack => 5,
        :defense => 5,
        :engineering => 5,
        :location => explorer_object.location
      )

      if explorer_ship.id?
        @my_player.balance -= PriceList.ship
        puts "New Ship created sending to #{expand_planet.name}"
        explorer_ship = explorer_ship.reload
        explorer_ship.update_attributes(:action => "ATTACK")
        if explorer_ship.course_control((Functions.distance_between(explorer_object, expand_planet) / 2).to_i, nil, expand_planet.location)
          explorer_ship.type = "Travelling"
          explorer_ship.objective = expand_planet
          @travelling_ships << explorer_ship
          @objective_planets.delete(expand_planet)
        end

        # Load the ship into our array
        @ships << explorer_ship
      end
    elsif explorer_object.is_a?(MyShip) #&& explorer_object.type == "Travelling"
                                        #puts "Travelling ship #{explorer_object.name} is queued to travel to #{expand_planet.name}"
                                        #explorer_object.queue += expand_planet
                                        # Do nothing because this ship is still travelling
                                        #puts "The closest object to #{expand_planet.name} is the ship #{explorer_object.id}:#{explorer_object.name}"
      if explorer_object.at_destination? && (@planets.include?(explorer_object.objective) || explorer_object.ships_in_range.size > 0)
        puts "The ship #{explorer_object.name} is now travelling to #{expand_planet.name}"
        if explorer_object.course_control((Functions.distance_between(explorer_object, expand_planet) / 2).to_i, nil, expand_planet.location)
          explorer_object.objective = expand_planet
          explorer_object.update_attributes(:action => "ATTACK", :action_target_id => nil)
          @objective_planets.delete(expand_planet)
        end
      end
    end
    #end
    #end
  end

  def calculate_efficient_travel(to)
    # first calculate if a new ship were to go there
    closest_planet = @planets.sort { |p| Functions.distance_between(p, to) }.first

    # calculate the closest travelling ship and it's distance to it's target and the distance
    # from the target to our target destination
    if @travelling_ships.size > 0
      closest_travelling_ship = @travelling_ships.sort { |ts|
        (ts.distance_from_objective + Functions.distance_between(ts.objective, to)) / ts.max_speed
      }.first
    end

    vals = {}
    vals.merge!(closest_planet => Functions.distance_between(closest_planet, to) / (PriceList.ship + Schemaverse.available_income(@ships))) if @ships.size < 1700
    vals.merge!(closest_travelling_ship => Functions.distance_between(closest_travelling_ship.objective, to) / (PriceList.ship + Schemaverse.available_income(@ships))) if closest_travelling_ship

    unless vals.empty?
      # Return the object to send
      vals.sort_by { |name, tics| tics }.to_a.first[0]
    else
      return nil
    end

  end

  def call_for_reinforcements(ship)
    planet = ship.objective.closest_planets.where("conqueror_id = ?", @my_player.id).first
    if planet && @my_player.total_resources >= (PriceList.ship + (PriceList.attack * 200) + (PriceList.defense * 200)) * 20
      20.times do
        cost = PriceList.ship + (PriceList.attack * 200) + (PriceList.defense * 200)
        @my_player.convert_fuel_to_money(cost) if @my_player.balance < cost
        armada_ship = MyShip.create(
          :name => "#{USERNAME}-armada",
          :prospecting => 5,
          :attack => 5,
          :defense => 5,
          :engineering => 5,
          :location => planet.location
        )

        if armada_ship.id?
          @my_player.balance -= PriceList.ship
          puts "New Ship created sending to #{planet.name}"
          armada_ship = armada_ship.reload
          armada_ship.update_attributes(:action => "ATTACK")

          @my_player.convert_fuel_to_money((200 * PriceList.attack).to_i) if @my_player.balance < (200 * PriceList.attack)
          armada_ship.upgrade('ATTACK', 200)
          armada_ship.update_attribute("name", "#{USERNAME}-armada")
          @my_player.balance -= 200 * PriceList.attack

          @my_player.convert_fuel_to_money((200 * PriceList.attack).to_i) if @my_player.balance < (200 * PriceList.attack)
          armada_ship.upgrade('DEFENSE', 200)
          armada_ship.update_attribute("name", "#{USERNAME}-armada")
          @my_player.balance -= 200 * PriceList.defense

          if armada_ship.course_control((Functions.distance_between(armada_ship, planet) / 2).to_i, nil, ship.location)
            armada_ship.type = "Armada"
            armada_ship.objective = ship.objective
          end

          # Load the ship into our array
          puts "Sending aramda ship to #{ship.objective.name}"
          @ships << armada_ship
        end
      end
    end

  end

  class << self

    def fuel_needed_for_next_tic(ships)
      ships.select { |s| s.type.eql?("Travelling") }.inject(0) do |result, ship|
        # Keep the fuel above 50% at all times
        if ship.current_fuel < (ship.max_fuel / 2)
          result += ship.max_fuel - ship.current_fuel
        else
          result += 0
        end
      end
    end

    def estimated_income(ships)
      mining_gain_per_prospecting = 16.5
      ships.select { |s| s.action && s.action.strip == 'MINE' }.sum(&:prospecting) * mining_gain_per_prospecting
    end

    def total_expenses(ships)
      price_for_fuel = 1
      Schemaverse.fuel_needed_for_next_tic(ships) * price_for_fuel
    end

    def available_income(ships)
      Schemaverse.estimated_income(ships) - Schemaverse.total_expenses(ships)
    end
  end

end
