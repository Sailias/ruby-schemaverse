module Variables

  def determine_home
    if Planet.home.nil?
      if @home
        @home = @home.closest_planets(1).my_planets.first
      else
        @home = Planet.my_planets.first
      end
      @home.update_attribute('name', Planet.my_home_name) if @home
    elsif Planet.where(:name => Planet.my_home_name).size > 1
      @home ||= Planet.home
      (Planet.where(:name => Planet.my_home_name).all - [@home]).each do |p|
        p.update_attribute("name", "my_planet_recaptured")
      end
    else
      @home = Planet.home
    end
  end

  def set_up_variables
    @my_player = MyPlayer.first
    determine_home
    @max_ship_skill = Functions.get_numeric_variable('MAX_SHIP_SKILL')
    @max_ship_fuel = Functions.get_numeric_variable('MAX_SHIP_FUEL')
    @max_ship_speed = Functions.get_numeric_variable('MAX_SHIP_SPEED')
    @ships = MyShip.select("name, location, destination, current_health").all
    @travelling_ships = []
    @armada_ships = []

    all_planets = Planet.all
    @ships.select { |s| !s.destination.blank? }.each do |ship|
      if p = all_planets.select { |p| p.location.eql?(ship.destination) }.first
        ship.objective = p
      end
    end

    @travelling_ships = @ships.select { |s| s.objective && !s.name.include?("armada") }
    @armada_ships = @ships.select { |s| s.objective && s.name.include?("armada") }

    @lost_ships = []
    @my_planets = Planet.my_planets.all

    @planets = [@home]
    @objective_planets = []
    @armada_planets = []
    @armada_targets = []
    @lost_planets = []
    @tic = 0

    @number_of_total_ships_allowed = 2001
    @number_of_ships_in_armada = 20
    @number_of_armada_groups = 75
    @number_of_travelling_ships = 500
    @number_of_miners_allowed = @number_of_total_ships_allowed - @number_of_travelling_ships - (@number_of_armada_groups * @number_of_ships_in_armada)

    @armada_ships.each do |ship|
      #@armada_targets << ship.objective unless @armada_planets.include?(ship.objective)
    end

    @planets_to_create_objects = []
    @travellers_to_deploy = []
    @armadas_to_deploy = []

    @objective_planets = []
    #@objective_planets = Planet.not_my_planets.select("id, name, location, conqueror_id, planets.location<->POINT('#{@home.location}') as distance").order("distance ASC").all

    @trade_ships = []

    puts "populating trade data"
    @trade = MyTrade.create_trade
    #populate_trade_data

    puts "loading ships in range"
    @ships_in_range = ShipsInRange.all
  end

  def populate_tic_data

    begin

      puts "loading tic data"

      @my_player = MyPlayer.first
      @my_player.convert_money_to_fuel(@my_player.balance)

      @planets_to_create_objects = []
      @travellers_to_deploy = []
      @armadas_to_deploy = []

      puts "    reloading planets"
      my_planets = []
      my_planets = Planet.my_planets.order("planets.location<->POINT('#{@home.location}') DESC").all if @home
      new_planets = my_planets - @planets

      all_planets = Planet.all
      @objective_planets = []
      #@objective_planets = Planet.not_my_planets.select("id, name, location, conqueror_id, planets.location<->POINT('#{@home.location}') as distance").order("distance ASC").all

      puts "    renaming planets"
      new_planets.each_with_index do |planet, i|
        planet.update_attribute('name', Planet.get_new_planet_name) unless planet.eql?(@home) || planet.name.downcase.include?(USERNAME)
        #@objective_planets.delete(planet) if @objective_planets.index(planet)
      end

      #@lost_planets += @planets - my_planets
      @planets = my_planets

      puts "You own #{@planets.size} planets"

      @armada_planets = []
      @armada_targets = []

      #@lost_planets.each do |lost_planet|
      #  @armada_planets.unshift(lost_planet) unless @armada_planets.include?(lost_planet)
      #end

      @lost_planets = []
      @ships = []
      @travelling_ships = []
      @armada_ships = []
      @mining_ships = []
      @ships_in_range = []
      my_ships = []
      #my_ships = MyShip.select("name, location, destination, current_health, action, action_target_id").all
      my_ships = MyShip.all

      #new_ships = my_ships - @ships
      #@lost_ships += @ships - my_ships

      puts "    populating ship objective data"
      @ships = my_ships
      @ships.select { |s| !s.destination.blank? }.each do |ship|
        if p = all_planets.select { |p| p.location.eql?(ship.destination) }.first
          ship.objective = p
        end
      end

      @travelling_ships = @ships.select { |s| s.objective && !s.name.include?("armada") }
      @armada_ships = @ships.select { |s| s.objective && s.name.include?("armada") }
      @mining_ships = @ships.select { |s| s.action && s.action.strip.eql?("MINE") && !s.name.include?("armada") && !s.name.include?("traveller") }

      #@armada_ships.each do |ship|
      #  @armada_targets << ship.objective unless @armada_planets.include?(ship.objective)
        #@objective_planets -= [ship.objective]
        #@armada_planets -= [ship.objective]
      #end

      #@travelling_ships.each do |travelling_ship|
        #@objective_planets -= [travelling_ship.objective]
      #end

      # Add the planet back to the start of our objective planets
      #@lost_ships.collect(&:objective).compact.select { |o| o.is_a?(Planet) && !@planets.include?(o) }.each do |planet|
      #  @objective_planets << planet unless @objective_planets.include?(planet) || @planets.include?(planet)
      #end

      puts "    loading ships in range"
      @ships_in_range = ShipsInRange.all

    rescue Exception => e
      puts e.message
      puts e.backtrace
    end
  end

  def populate_trade_data
    swap_ships = MyShip.first(@trade.items.size)
    if @trade
      puts "    swapping ships into trade"

      trade_items = @trade.items.all
      TradeItem.trade_ships(swap_ships)

      puts "    populating ship data"
      TradeItem.delete_trades(trade_items.collect { |ti| ti.descriptor.to_s })
      #@trade.items.where(:id => trade_items.collect(&:id)).destroy_all

      # put the trade item into trade ships array
      @trade_ships += MyShip.where(:id => trade_items.collect(&:descriptor))

      TradeItem.trade_ships(@trade_ships)

      puts "    Removing swapping ships from trade"
      TradeItem.delete_trades(swap_ships.collect(&:id))
      #TradeItem.where(:id => swap_trade_items.collect(&:id)).destroy_all

    end
  end

end