class CategoryExpense {
  CategoryExpense({
    required this.categoryId,
    required this.categoryName,
    required this.amountMinor,
  }) {
    if (categoryId.trim().isEmpty) {
      throw ArgumentError.value(categoryId, 'categoryId', 'Must not be blank.');
    }
    if (categoryName.trim().isEmpty) {
      throw ArgumentError.value(
        categoryName,
        'categoryName',
        'Must not be blank.',
      );
    }
    if (amountMinor <= 0) {
      throw ArgumentError.value(amountMinor, 'amountMinor', 'Must be > 0.');
    }
  }

  final String categoryId;
  final String categoryName;
  final int amountMinor;
}
