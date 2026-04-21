import 'package:equatable/equatable.dart';

enum CustomCategoryType { expense, income }

class CustomCategory extends Equatable {
  final String id;
  final String name;
  final String icon;
  final CustomCategoryType type;
  final DateTime createdAt;

  const CustomCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.type,
    required this.createdAt,
  });

  CustomCategory copyWith({
    String? id,
    String? name,
    String? icon,
    CustomCategoryType? type,
    DateTime? createdAt,
  }) {
    return CustomCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [id, name, icon, type, createdAt];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'type': type == CustomCategoryType.expense ? 'expense' : 'income',
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  factory CustomCategory.fromJson(Map<String, dynamic> json) {
    return CustomCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String,
      type: json['type'] == 'income'
          ? CustomCategoryType.income
          : CustomCategoryType.expense,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
    );
  }
}
