import 'package:flutter/material.dart';

/// A basic item someone can ask for. They pick from this list rather than
/// typing, so a request can't carry anything personal. The server has the same
/// list (backend/internal/api/help_items.go); a test keeps them in step.
class SupplyItem {
  final String code;
  final String label;
  final IconData icon;
  const SupplyItem(this.code, this.label, this.icon);
}

const supplyItems = <SupplyItem>[
  SupplyItem('meal', 'A meal', Icons.restaurant_rounded),
  SupplyItem('water', 'Water', Icons.water_drop_rounded),
  SupplyItem('snacks', 'Snacks', Icons.cookie_rounded),
  SupplyItem('socks', 'Socks', Icons.checkroom_rounded),
  SupplyItem('underwear', 'Underwear', Icons.checkroom_rounded),
  SupplyItem('shirt', 'A shirt', Icons.checkroom_rounded),
  SupplyItem('pants', 'Pants', Icons.checkroom_rounded),
  SupplyItem('shoes', 'Shoes', Icons.hiking_rounded),
  SupplyItem('coat', 'A coat or jacket', Icons.checkroom_rounded),
  SupplyItem('hat_gloves', 'A hat and gloves', Icons.ac_unit_rounded),
  SupplyItem('rain_poncho', 'A rain poncho', Icons.umbrella_rounded),
  SupplyItem('blanket', 'A blanket', Icons.bed_rounded),
  SupplyItem('sleeping_bag', 'A sleeping bag', Icons.night_shelter_rounded),
  SupplyItem('tent_tarp', 'A tent or tarp', Icons.cabin_rounded),
  SupplyItem('backpack', 'A backpack', Icons.backpack_rounded),
  SupplyItem('hygiene_kit', 'A hygiene kit', Icons.clean_hands_rounded),
  SupplyItem('feminine', 'Feminine hygiene products', Icons.spa_rounded),
  SupplyItem('diapers', 'Diapers or baby supplies', Icons.child_friendly_rounded),
  SupplyItem('towel', 'A towel', Icons.dry_cleaning_rounded),
  SupplyItem('first_aid', 'First aid supplies', Icons.medical_services_rounded),
  SupplyItem('phone_charger', 'A phone charger', Icons.battery_charging_full_rounded),
  SupplyItem('bug_spray', 'Bug spray or sunscreen', Icons.wb_sunny_rounded),
];

/// Most things someone can ask for at once.
const kMaxSupplyItems = 10;

String supplyLabel(String code) => supplyItems.where((i) => i.code == code).firstOrNull?.label ?? code;

/// "Socks, a blanket and water"
String supplySummary(List<String> codes) {
  final labels = [for (final c in codes) supplyLabel(c).toLowerCase()];
  if (labels.isEmpty) return '';
  if (labels.length == 1) return labels.first;
  return '${labels.sublist(0, labels.length - 1).join(', ')} and ${labels.last}';
}
