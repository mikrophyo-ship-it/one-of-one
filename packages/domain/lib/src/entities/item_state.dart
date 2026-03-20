enum ItemState {
  drafted,
  minted,
  inInventory,
  soldUnclaimed,
  claimed,
  listedForResale,
  salePending,
  transferred,
  disputed,
  stolenFlagged,
  frozen,
  archived,
}

ItemState itemStateFromKey(String key) => switch (key) {
      'drafted' => ItemState.drafted,
      'minted' => ItemState.minted,
      'in_inventory' => ItemState.inInventory,
      'sold_unclaimed' => ItemState.soldUnclaimed,
      'claimed' => ItemState.claimed,
      'listed_for_resale' => ItemState.listedForResale,
      'sale_pending' => ItemState.salePending,
      'transferred' => ItemState.transferred,
      'disputed' => ItemState.disputed,
      'stolen_flagged' => ItemState.stolenFlagged,
      'frozen' => ItemState.frozen,
      'archived' => ItemState.archived,
      _ => throw ArgumentError('Unknown item state key: $key'),
    };

extension ItemStateX on ItemState {
  String get key => switch (this) {
        ItemState.drafted => 'drafted',
        ItemState.minted => 'minted',
        ItemState.inInventory => 'in_inventory',
        ItemState.soldUnclaimed => 'sold_unclaimed',
        ItemState.claimed => 'claimed',
        ItemState.listedForResale => 'listed_for_resale',
        ItemState.salePending => 'sale_pending',
        ItemState.transferred => 'transferred',
        ItemState.disputed => 'disputed',
        ItemState.stolenFlagged => 'stolen_flagged',
        ItemState.frozen => 'frozen',
        ItemState.archived => 'archived',
      };

  bool get isRestricted =>
      this == ItemState.disputed ||
      this == ItemState.stolenFlagged ||
      this == ItemState.frozen;
}
