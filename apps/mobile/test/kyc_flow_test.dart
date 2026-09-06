import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vesspay/core/routing/app_router.dart';
import 'package:vesspay/core/routing/app_routes.dart';
import 'package:vesspay/features/kyc/models/kyc_model.dart';
import 'package:vesspay/features/kyc/repositories/kyc_repository.dart';
import 'package:vesspay/features/kyc/screens/kyc_screen.dart';

class MockKycRepository implements KycRepository {
  final KycStatusModel status;
  final KycLinkModel link;
  int getLinkCallCount = 0;
  int getStatusCallCount = 0;

  MockKycRepository({
    KycStatusModel? status,
    KycLinkModel? link,
  })  : status = status ??
            KycStatusModel(
              onboardingStatus: 'DRAFT',
              enhancedKycStatus: 'NOT_STARTED',
            ),
        link = link ??
            KycLinkModel(
              url: 'https://in.sumsub.com/websdk/p/sbx_test123',
              stage: 'ONBOARDING',
            );

  @override
  Future<KycLinkModel> getKycLink() async {
    getLinkCallCount++;
    return link;
  }

  @override
  Future<KycStatusModel> getKycStatus() async {
    getStatusCallCount++;
    return status;
  }
}

void main() {
  group('WeWire Hosted KYC Flow Tests', () {
    test('KycModel parses JSON contract correctly', () {
      final link = KycLinkModel.fromJson({
        'url': 'https://in.sumsub.com/websdk/p/sbx_abc',
        'stage': 'ONBOARDING',
      });
      expect(link.url, equals('https://in.sumsub.com/websdk/p/sbx_abc'));
      expect(link.stage, equals('ONBOARDING'));

      final draftStatus = KycStatusModel.fromJson({
        'onboardingStatus': 'DRAFT',
        'enhancedKycStatus': 'NOT_STARTED',
      });
      expect(draftStatus.isApproved, isFalse);
      expect(draftStatus.isInReview, isFalse);
      expect(draftStatus.displayStatus, equals('Action Required'));

      final approvedStatus = KycStatusModel.fromJson({
        'onboardingStatus': 'APPROVED',
        'enhancedKycStatus': 'NOT_STARTED',
      });
      expect(approvedStatus.isApproved, isTrue);
      expect(approvedStatus.displayStatus, equals('Verified'));
    });

    testWidgets('KycScreen renders header, status card, and action buttons', (tester) async {
      final mockRepo = MockKycRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            kycRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const MaterialApp(
            home: KycScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Identity Verification'), findsOneWidget);
      expect(find.text('WeWire Identity Verification'), findsOneWidget);
      expect(find.text('Action Required'), findsOneWidget);
      expect(find.byKey(const Key('launch_kyc_button')), findsOneWidget);
      expect(find.byKey(const Key('refresh_kyc_button')), findsOneWidget);
      expect(find.text('Launch Verification Portal'), findsOneWidget);
      expect(find.text('Check Verification Status'), findsOneWidget);
    });

    testWidgets('Tapping refresh button requests updated KYC status', (tester) async {
      final mockRepo = MockKycRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            kycRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const MaterialApp(
            home: KycScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(mockRepo.getStatusCallCount, equals(1));

      final refreshBtn = find.byKey(const Key('refresh_kyc_button'));
      await tester.ensureVisible(refreshBtn);
      await tester.pumpAndSettle();
      await tester.tap(refreshBtn);
      await tester.pumpAndSettle();

      expect(mockRepo.getStatusCallCount, greaterThanOrEqualTo(2));
    });

    testWidgets('Home screen Identity Verification card navigates to KycScreen', (tester) async {
      final mockRepo = MockKycRepository();
      final router = createAppRouter(initialLocation: AppRoutes.home);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            kycRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Open More Options from profile avatar
      await tester.tap(find.byIcon(Icons.person_outline_rounded));
      await tester.pumpAndSettle();

      final kycCard = find.byKey(const Key('home_kyc_card'));
      expect(kycCard, findsOneWidget);
      expect(find.text('WeWire hosted compliance portal'), findsOneWidget);

      await tester.tap(kycCard);
      await tester.pumpAndSettle();

      // Should now be on KycScreen
      expect(find.text('WeWire Identity Verification'), findsOneWidget);
      expect(find.byKey(const Key('launch_kyc_button')), findsOneWidget);
    });
  });
}
