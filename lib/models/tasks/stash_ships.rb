class StashShips
  @queue = :stash_ships

  def self.perform(n)
    TradeItem.trade_number_of_ships(n)
  end
end