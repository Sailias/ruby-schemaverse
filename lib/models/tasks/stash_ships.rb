class StashShips
  @queue = :stash_ships

  def self.perform(n, planets_to_create_objects, travellers_to_deploy, armadas_to_deploy)
    if TradeItem.trade_number_of_ships(n)
      planets_to_create_objects.each do |arr|
        Resque.enqueue(CreateShipsAtPlanet, arr[0], arr[1], arr[2], arr[3])
      end

      travellers_to_deploy.each do |travs|
        Resque.enqueue(TravellingShips, travs[0], travs[1], travs[2])
      end

      armadas_to_deploy.each do |armad|
        Resque.enqueue(ArmadaShips, armad[0], armad[1], armad[2])
      end

      puts "Destroying all trades"
      Resque.enqueue(UnstashShips)
    end
  end
end