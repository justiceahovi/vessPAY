import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesspay/core/navigation/floating_bottom_nav_bar.dart';
import 'package:vesspay/core/theme/app_colors.dart';

void main() {
  group('FloatingBottomNavBar Widget Tests', () {
    testWidgets('Renders 3 navigation items: Profile, Home, Transactions',
        (WidgetTester tester) async {
      int tappedIndex = -1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: FloatingBottomNavBar(
              currentIndex: 1,
              onTabSelected: (index) => tappedIndex = index,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Transactions'), findsOneWidget);

      expect(find.byKey(const Key('nav_item_profile')), findsOneWidget);
      expect(find.byKey(const Key('nav_item_home')), findsOneWidget);
      expect(find.byKey(const Key('nav_item_transactions')), findsOneWidget);

      // Home sits in the centre and is selected at currentIndex 1 with blue pill background and onPrimary icon
      final homeIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('nav_item_home')),
          matching: find.byType(Icon),
        ),
      );
      expect(homeIcon.color, equals(AppColors.onPrimary));

      final homeContainer = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byKey(const Key('nav_item_home')),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect((homeContainer.decoration as BoxDecoration).color, equals(AppColors.primary));

      await tester.tap(find.byKey(const Key('nav_item_profile')));
      await tester.pumpAndSettle();
      expect(tappedIndex, equals(0));

      await tester.tap(find.byKey(const Key('nav_item_transactions')));
      await tester.pumpAndSettle();
      expect(tappedIndex, equals(2));

      await tester.tap(find.byKey(const Key('nav_item_home')));
      await tester.pumpAndSettle();
      expect(tappedIndex, equals(1));
    });

    testWidgets('Highlights Transactions when it is the active tab',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: FloatingBottomNavBar(
              currentIndex: 2,
              onTabSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final transactionsIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('nav_item_transactions')),
          matching: find.byType(Icon),
        ),
      );
      expect(transactionsIcon.color, equals(AppColors.onPrimary));

      final transContainer = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byKey(const Key('nav_item_transactions')),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect((transContainer.decoration as BoxDecoration).color, equals(AppColors.primary));

      final homeIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('nav_item_home')),
          matching: find.byType(Icon),
        ),
      );
      expect(homeIcon.color, equals(AppColors.muted));
    });
  });
}
