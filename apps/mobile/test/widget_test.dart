import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesspay/core/providers.dart';
import 'package:vesspay/core/routing/app_router.dart';
import 'package:vesspay/core/routing/app_routes.dart';
import 'package:vesspay/core/storage/token_storage.dart';
import 'package:vesspay/main.dart';

void main() {
  testWidgets('VessPayApp smoke test launches cleanly to splash',
      (WidgetTester tester) async {
    final tokenStorage = InMemoryTokenStorage();
    final router = createAppRouter(
      initialLocation: AppRoutes.splash,
      splashMinDuration: const Duration(milliseconds: 100),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(tokenStorage),
          routerProvider.overrideWithValue(router),
        ],
        child: const VessPayApp(),
      ),
    );

    // Verify VessPay brand wordmark is rendered on initial launch
    expect(find.text('VessPay'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Drain timer cleanly
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
  });
}
