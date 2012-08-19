class UnstashShips
  @queue = :unstash_ships

  def self.perform
    unless TradeItem.destroy_all_trades
      Resque.enqueue(UnstashShips)
    end
  end
end