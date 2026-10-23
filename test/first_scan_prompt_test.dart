import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anthrofit/app.dart';
import 'package:anthrofit/auth/account_store.dart';
import 'package:anthrofit/data/measurement_repository.dart';
import 'package:anthrofit/data/profile_repository.dart';
import 'package:anthrofit/data/storage_scope.dart';
import 'package:anthrofit/scan/mock_scan_source.dart';
import 'package:anthrofit/screens/scan/scan_choice_screen.dart';

import 'test_helpers.dart';

Badge _scanBadge(WidgetTester tester) =>
    tester.widget<Badge>(find.byKey(const ValueKey('scan-fab-badge')));

void main() {
  useExerciseLibrary();

  testWidgets('a profile with no scans is prompted to scan', (tester) async {
    seedSavedProfile();
    await tester.pumpWidget(AnthrofitApp(authService: FakeAuthService()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('scan-tip')), findsOneWidget);
    expect(_scanBadge(tester).isLabelVisible, isTrue);

    await tester.tap(find.text('Tap here to take your first body scan'));
    await tester.pumpAndSettle();
    expect(find.byType(ScanChoiceScreen), findsOneWidget);
  });

  testWidgets('the scan tip can be dismissed', (tester) async {
    seedSavedProfile();
    await tester.pumpWidget(AnthrofitApp(authService: FakeAuthService()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('scan-tip-close')));
    await tester.pump();
    expect(find.byKey(const ValueKey('scan-tip')), findsNothing);
  });

  testWidgets('no prompt once a scan is saved', (tester) async {
    SharedPreferences.setMockInitialValues({
      AccountStore.guestModeKey: 'guest',
      ProfileRepository.storageKey: jsonEncode(sampleProfile.toJson()),
      StorageScope.guest.key(MeasurementRepository.storageKey): jsonEncode({
        'measurements': [mockMeasurement().toJson()],
      }),
    });
    await tester.pumpWidget(AnthrofitApp(authService: FakeAuthService()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('scan-tip')), findsNothing);
    expect(_scanBadge(tester).isLabelVisible, isFalse);
  });
}
