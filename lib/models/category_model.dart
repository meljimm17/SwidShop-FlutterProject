/// A marketplace category. Firestore document id is an auto id.
class CategoryModel {
  const CategoryModel({
    required this.categoryId,
    required this.name,
    this.iconName = '',
    this.sortOrder = 0,
  });

  final String categoryId;
  final String name;

  /// Logical icon name mapped to a Material icon in the UI layer.
  final String iconName;

  final int sortOrder;

  factory CategoryModel.fromMap(String categoryId, Map<String, dynamic> map) {
    return CategoryModel(
      categoryId: categoryId,
      name: map['name'] as String? ?? '',
      iconName: map['iconName'] as String? ?? '',
      sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'categoryId': categoryId,
        'name': name,
        'iconName': iconName,
        'sortOrder': sortOrder,
      };

  CategoryModel copyWith({
    String? categoryId,
    String? name,
    String? iconName,
    int? sortOrder,
  }) =>
      CategoryModel(
        categoryId: categoryId ?? this.categoryId,
        name: name ?? this.name,
        iconName: iconName ?? this.iconName,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}
