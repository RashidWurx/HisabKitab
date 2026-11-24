import 'package:material_ui/material_ui.dart';

/// Icons users can pick for sources, accounts and categories.
/// The key is what is stored in the database.
const Map<String, IconData> appIcons = {
  'bank': Icons.account_balance_outlined,
  'wallet': Icons.account_balance_wallet_outlined,
  'phone': Icons.smartphone_outlined,
  'cash': Icons.payments_outlined,
  'card': Icons.credit_card_outlined,
  'savings': Icons.savings_outlined,
  'work': Icons.work_outline,
  'laptop': Icons.laptop_mac,
  'store': Icons.storefront_outlined,
  'business': Icons.business_center_outlined,
  'gift': Icons.card_giftcard_outlined,
  'family': Icons.family_restroom,
  'people': Icons.people_outline,
  'fuel': Icons.local_gas_station_outlined,
  'wifi': Icons.wifi,
  'food': Icons.restaurant_outlined,
  'receipt': Icons.receipt_long_outlined,
  'home': Icons.home_outlined,
  'shopping': Icons.shopping_bag_outlined,
  'health': Icons.favorite_border,
  'subscriptions': Icons.autorenew,
  'category': Icons.sell_outlined,
  'travel': Icons.flight_outlined,
  'car': Icons.directions_car_outlined,
  'school': Icons.school_outlined,
  'game': Icons.sports_esports_outlined,
  'movie': Icons.movie_outlined,
  'pets': Icons.pets_outlined,
  'tools': Icons.build_outlined,
  'cloud': Icons.cloud_outlined,
  'star': Icons.star_border,
  'coffee': Icons.local_cafe_outlined,
};

IconData iconFor(String key) => appIcons[key] ?? Icons.sell_outlined;

/// Colours users can pick (ARGB ints, stored in the database).
const List<int> appPalette = [
  0xFF112E4E,
  0xFF2A4E76,
  0xFF1F7A1F,
  0xFF00897B,
  0xFFD98A00,
  0xFFFF5722,
  0xFFCD1F1F,
  0xFFE91E63,
  0xFF9C27B0,
  0xFF5E35B1,
  0xFF3F51B5,
  0xFF795548,
  0xFF607D8B,
];
