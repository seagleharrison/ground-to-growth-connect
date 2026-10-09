import 'package:flutter/material.dart';

import '../models/models.dart';

extension HelpCategoryIcon on HelpCategory {
  IconData get icon => switch (this) {
    HelpCategory.food => Icons.restaurant_rounded,
    HelpCategory.shelter => Icons.home_rounded,
    HelpCategory.ride => Icons.directions_car_rounded,
    HelpCategory.documents => Icons.badge_rounded,
    HelpCategory.clothing => Icons.checkroom_rounded,
    HelpCategory.health => Icons.medical_services_rounded,
    HelpCategory.work => Icons.work_rounded,
    HelpCategory.other => Icons.help_outline_rounded,
    HelpCategory.supplies => Icons.inventory_2_rounded,
  };
}
