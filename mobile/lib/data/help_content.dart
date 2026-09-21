import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/models.dart';

class HelpLink {
  final String label;
  final String url;
  const HelpLink(this.label, this.url);

  factory HelpLink.fromJson(Map<String, dynamic> json) => HelpLink(json['label'] as String, json['url'] as String);
}

class HelpPhone {
  final String label;
  final String display; // what the person sees
  final String dial; // digits only, what the phone dials
  const HelpPhone(this.label, this.display, this.dial);

  factory HelpPhone.fromJson(Map<String, dynamic> json) =>
      HelpPhone(json['label'] as String? ?? '', json['display'] as String, json['dial'] as String);
}

class HelpSection {
  final String heading;
  final List<String> items;
  final bool numbered;
  const HelpSection(this.heading, this.items, {this.numbered = false});

  factory HelpSection.fromJson(Map<String, dynamic> json) => HelpSection(
        json['heading'] as String,
        [for (final i in json['items'] as List) i as String],
        numbered: json['numbered'] as bool? ?? false,
      );
}

const _icons = <String, IconData>{
  'description': Icons.description_outlined,
  'badge': Icons.badge_outlined,
  'contact_page': Icons.contact_page_outlined,
  'military_tech': Icons.military_tech_outlined,
  'health_and_safety': Icons.health_and_safety_outlined,
  'local_hospital': Icons.local_hospital_outlined,
  'verified_user': Icons.verified_user_outlined,
  'elderly': Icons.elderly_outlined,
  'receipt_long': Icons.receipt_long_outlined,
  'restaurant': Icons.restaurant_outlined,
  'favorite': Icons.favorite_border_rounded,
};

/// One how-to or program, shown the same way everywhere: a short summary,
/// sections of plain-language points, links, and phone numbers to tap.
class HelpTopic {
  final String id;
  final String title;
  final IconData icon;
  final String summary;
  final List<HelpSection> sections;
  final List<HelpLink> links;
  final List<HelpPhone> phones;

  /// If this topic is about getting one of the core documents, the person can
  /// jump straight to adding it to their vault afterwards.
  final DocumentType? relatedDocument;

  const HelpTopic({
    required this.id,
    required this.title,
    required this.icon,
    required this.summary,
    required this.sections,
    this.links = const [],
    this.phones = const [],
    this.relatedDocument,
  });

  factory HelpTopic.fromJson(Map<String, dynamic> json) => HelpTopic(
        id: json['id'] as String,
        title: json['title'] as String,
        icon: _icons[json['icon']] ?? Icons.info_outline_rounded,
        summary: json['summary'] as String,
        sections: [for (final s in json['sections'] as List) HelpSection.fromJson(s as Map<String, dynamic>)],
        links: [for (final l in (json['links'] as List? ?? [])) HelpLink.fromJson(l as Map<String, dynamic>)],
        phones: [for (final p in (json['phones'] as List? ?? [])) HelpPhone.fromJson(p as Map<String, dynamic>)],
        relatedDocument: json['relatedDocument'] == null ? null : DocumentType.fromWire(json['relatedDocument'] as String),
      );
}

/// A real place in Savannah someone can go to.
class HelpPlace {
  final String id;
  final String name;
  final String category;
  final String address;
  final double lat;
  final double lng;
  final HelpPhone phone;
  final String url;
  final String? hours;
  final String note;
  final String verifiedOn;

  const HelpPlace({
    required this.id,
    required this.name,
    required this.category,
    required this.address,
    required this.lat,
    required this.lng,
    required this.phone,
    required this.url,
    this.hours,
    required this.note,
    required this.verifiedOn,
  });

  factory HelpPlace.fromJson(Map<String, dynamic> json) => HelpPlace(
        id: json['id'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
        address: json['address'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        phone: HelpPhone.fromJson({'label': json['name'], ...(json['phone'] as Map<String, dynamic>)}),
        url: json['url'] as String,
        hours: json['hours'] as String?,
        note: json['note'] as String,
        verifiedOn: json['verifiedOn'] as String,
      );
}

/// Everything on the Resources tab. It comes from the server (so wording,
/// prices and phone numbers can be corrected without a new app release), with
/// a copy bundled in the app for when there's no signal.
class HelpContent {
  final String updatedAt; // yyyy-MM-dd the content was last reviewed
  final List<HelpTopic> documentGuides;
  final List<HelpTopic> benefitPrograms;
  final List<HelpPlace> places;

  const HelpContent({
    required this.updatedAt,
    required this.documentGuides,
    required this.benefitPrograms,
    required this.places,
  });

  factory HelpContent.fromJson(Map<String, dynamic> json) => HelpContent(
        updatedAt: json['updatedAt'] as String,
        documentGuides: [for (final t in json['documentGuides'] as List) HelpTopic.fromJson(t as Map<String, dynamic>)],
        benefitPrograms: [for (final t in json['benefitPrograms'] as List) HelpTopic.fromJson(t as Map<String, dynamic>)],
        places: [for (final p in (json['places'] as List? ?? [])) HelpPlace.fromJson(p as Map<String, dynamic>)],
      );

  static Future<HelpContent> loadBundled() async {
    final raw = await rootBundle.loadString('assets/resources.json');
    return HelpContent.fromRaw(raw);
  }

  /// Reads the server's JSON. Throws [FormatException] if it isn't the expected shape,
  /// so a bad response can never replace good content.
  static HelpContent fromRaw(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) throw const FormatException('Resources content must be a JSON object');
    return HelpContent.fromJson(decoded);
  }
}

// The 911 and 988 numbers never depend on the network or the server.
const emergencyPhone = HelpPhone('Emergency', '911', '911');
const crisisPhone = HelpPhone('Crisis line (call or text)', '988', '988');
const localHelpPhone = HelpPhone('Local help (food, shelter, more)', '211', '211');
