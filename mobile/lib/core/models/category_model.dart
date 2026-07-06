import 'package:companion_ranchi/core/models/json_utils.dart';

/// An activity category (categories table). Returned by
/// `GET /companions/categories` and `GET /meta/config`.
class CategoryModel {
  const CategoryModel({
    required this.id,
    required this.slug,
    required this.name,
    this.iconUrl,
    this.sortOrder = 0,
    this.isActive = true,
  });

  final String id;

  /// Stable slug, e.g. `coffee-partner`.
  final String slug;
  final String name;
  final String? iconUrl;
  final int sortOrder;
  final bool isActive;

  factory CategoryModel.fromJson(Map<String, dynamic> json) => CategoryModel(
        id: J.asString(json['id']),
        slug: J.asString(json['slug']),
        name: J.asString(json['name']),
        iconUrl: J.asStringOrNull(json['iconUrl']),
        sortOrder: J.asInt(json['sortOrder']),
        isActive: J.asBool(json['isActive'], true),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'slug': slug,
        'name': name,
        'iconUrl': iconUrl,
        'sortOrder': sortOrder,
        'isActive': isActive,
      };
}
