import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ground_to_growth_connect/util/supply_items.dart';

void main() {
  test("the list of basic items is the same one the server accepts", () {
    final server = File('../backend/internal/api/help_items.go').readAsStringSync();
    final serverCodes = RegExp(r'\{"([a-z_]+)", "([^"]+)"\}').allMatches(server).map((m) => (m.group(1)!, m.group(2)!)).toList();
    expect(serverCodes, isNotEmpty);
    expect([for (final i in supplyItems) (i.code, i.label)], serverCodes, reason: 'keep lib/util/supply_items.dart and backend/internal/api/help_items.go in step');
  });

  test('items read naturally in a sentence', () {
    expect(supplySummary(['socks']), 'socks');
    expect(supplySummary(['socks', 'blanket']), 'socks and a blanket');
    expect(supplySummary(['water', 'socks', 'blanket']), 'water, socks and a blanket');
    expect(supplySummary([]), '');
  });

  test('every code is unique and the cap matches the server', () {
    expect({for (final i in supplyItems) i.code}.length, supplyItems.length);
    final server = File('../backend/internal/api/help_items.go').readAsStringSync();
    expect(RegExp(r'maxSupplyItems = (\d+)').firstMatch(server)!.group(1), '$kMaxSupplyItems');
  });
}
