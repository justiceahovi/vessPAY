import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesspay/core/navigation/floating_bottom_nav_bar.dart';
import 'package:vesspay/core/theme/app_colors.dart';

void main() {
  group('FloatingBottomNavBar Widget Tests', () {
    testWidgets('Renders 3 floating navigation items: Home, Pay, Cards',
        (WidgetTester tester) async {
      int tappedIndex = -1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: FloatingBottomNavBar(
              currentIndex: 0,
              thirdTabLabel: 'Cards',
              onTabSelected: (index) => tappedIndex = index,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Pay'), findsOneWidget);
      expect(find.text('Cards'), findsOneWidget);

      expect(find.byKey(const Key('nav_item_home')), findsOneWidget);
      expect(find.byKey(const Key('nav_item_pay')), findsOneWidget);
      expect(find.byKey(const Key('nav_item_cards')), findsOneWidget);

      // Verify Home is selected at currentIndex 0
      final homeIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('nav_item_home')),
          matching: find.byType(Icon),
        ),
      );
      expect(homeIcon.color, equals(AppColors.primary));

      // Tap Pay pill
      await tester.tap(find.byKey(const Key('nav_item_pay')));
      await tester.pumpAndSettle();
      expect(tappedIndex, equals(1));

      // Tap Cards pill
      await tester.tap(find.byKey(const Key('nav_item_cards')));
      await tester.pumpAndSettle();
      expect(tappedIndex, equals(2));

      // Tap Home pill
      await tester.tap(find.byKey(const Key('nav_item_home')));
      await tester.pumpAndSettle();
      expect(tappedIndex, equals(0));
    });

    testWidgets('Renders with custom thirdTabLabel such as Wallet',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: FloatingBottomNavBar(
              currentIndex: 2,
              thirdTabLabel: 'Wallet',
              onTabSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Wallet'), findsOneWidget);
      expect(find.text('Cards'), findsNothing);

      // Verify Wallet (index 2) is selected
      final walletIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('nav_item_cards')),
          matching: find.byType(Icon),
        ),
      );
      expect(walletIcon.color, equals(AppColors.primary));
    });
  });
}
