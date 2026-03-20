String formatCurrency(int cents) {
  final double amount = cents / 100;
  return '\$${amount.toStringAsFixed(2)}';
}
