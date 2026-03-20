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
