class StashShips
  @queue = :stash_ships

  def self.perform(n, planets_to_create_objects)
    if TradeItem.trade_number_of_ships(n)
      planets_to_create_objects.each do |arr|
        Resque.enqueue(CreateShipsAtPlanet, arr[0], arr[1], arr[2], arr[3])
      end

      puts "Destroying all trades"
      Resque.enqueue(UnstashShips)
    end
  end
end