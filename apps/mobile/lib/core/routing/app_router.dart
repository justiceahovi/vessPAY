import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/signup_screen.dart';
import '../../features/kyc/screens/kyc_screen.dart';
import '../../features/wallet/screens/add_money_screen.dart';
import '../../features/wallet/screens/wallet_currency_selection_screen.dart';
import '../../features/wallet/screens/wallet_screen.dart';
import '../../features/pay/models/transaction_model.dart';
import '../../features/pay/screens/pay_anyone_flow_screen.dart';
import '../../features/pay/screens/payment_review_screen.dart';
import '../../features/pay/screens/payment_processing_screen.dart';
import '../../features/pay/screens/payment_success_screen.dart';
import '../../features/pay/screens/payment_failure_screen.dart';
import '../../features/pay/screens/transaction_list_screen.dart';
import '../../features/pay/screens/transaction_detail_screen.dart';
import '../../features/placeholders/placeholder_screens.dart';
import '../../features/splash/screens/splash_screen.dart';
import '../navigation/main_app_shell.dart';
import 'app_routes.dart';


/// Function to generate GoRouter instance with configurable initial route & splash duration
GoRouter createAppRouter({
  String initialLocation = AppRoutes.splash,
  Duration? splashMinDuration,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        builder: (context, state) => SplashScreen(
          minDisplayDuration:
              splashMinDuration ?? const Duration(milliseconds: 1100),
        ),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        name: 'onboarding',
        builder: (context, state) => const OnboardingPlaceholderScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.signup,
        name: 'signup',
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: AppRoutes.walletCurrencySetup,
        name: 'wallet-currency-setup',
        builder: (context, state) => WalletCurrencySelectionScreen(
          nextRoute: state.extra is String
              ? state.extra as String
              : AppRoutes.travelModeSetup,
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => MainAppShell(
          currentLocation: state.uri.path,
          child: child,
        ),
        routes: [
          GoRoute(
            path: AppRoutes.travelModeSetup,
            name: 'travel-mode-setup',
            builder: (context, state) =>
                const TravelModeSetupPlaceholderScreen(),
          ),
          GoRoute(
            path: AppRoutes.home,
            name: 'home',
            builder: (context, state) => const HomePlaceholderScreen(),
          ),
          GoRoute(
            path: AppRoutes.kycVerification,
            name: 'kyc-verification',
            builder: (context, state) => const KycScreen(),
          ),
          GoRoute(
            path: AppRoutes.wallet,
            name: 'wallet',
            builder: (context, state) => const WalletScreen(),
          ),
          GoRoute(
            path: AppRoutes.addMoney,
            name: 'add-money',
            builder: (context, state) => const AddMoneyScreen(),
          ),
          GoRoute(
            path: AppRoutes.payAnyone,
            name: 'pay-anyone',
            builder: (context, state) => const PayAnyoneFlowScreen(),
          ),
          GoRoute(
            path: AppRoutes.paymentReview,
            name: 'payment-review',
            builder: (context, state) => const PaymentReviewScreen(),
          ),
          GoRoute(
            path: AppRoutes.paymentProcessing,
            name: 'payment-processing',
            builder: (context, state) {
              final extra = state.extra;
              String txId = '';
              TransactionModel? initialTx;
              if (extra is Map<String, dynamic>) {
                txId = extra['transactionId'] as String? ?? '';
                initialTx = extra['initialTransaction'] as TransactionModel?;
              } else if (extra is String) {
                txId = extra;
              }
              return PaymentProcessingScreen(
                transactionId: txId,
                initialTransaction: initialTx,
              );
            },
          ),
          GoRoute(
            path: AppRoutes.paymentSuccess,
            name: 'payment-success',
            builder: (context, state) {
              final extra = state.extra;
              final tx = extra is TransactionModel
                  ? extra
                  : TransactionModel(
                      id: 'unknown',
                      type: 'payout',
                      status: 'COMPLETED',
                      sourceCurrency: 'USD',
                      sourceAmount: 0.0,
                      destinationCurrency: 'GHS',
                      destinationAmount: 0.0,
                      fee: 0.0,
                      exchangeRate: 1.0,
                      createdAt: DateTime.now(),
                    );
              return PaymentSuccessScreen(transaction: tx);
            },
          ),
          GoRoute(
            path: AppRoutes.paymentFailure,
            name: 'payment-failure',
            builder: (context, state) {
              final extra = state.extra;
              TransactionModel? tx;
              String? reason;
              if (extra is TransactionModel) {
                tx = extra;
              } else if (extra is Map<String, dynamic>) {
                tx = extra['transaction'] as TransactionModel?;
                reason = extra['reason'] as String?;
              }
              return PaymentFailureScreen(
                transaction: tx,
                failureReason: reason,
              );
            },
          ),
          GoRoute(
            path: AppRoutes.transactionList,
            name: 'transactions',
            builder: (context, state) => const TransactionListScreen(),
          ),
          GoRoute(
            path: AppRoutes.transactionDetail,
            name: 'transaction-detail',
            builder: (context, state) {
              final extra = state.extra;
              TransactionModel? tx;
              String? id;
              if (extra is TransactionModel) {
                tx = extra;
                id = extra.id;
              } else if (extra is String) {
                id = extra;
              } else if (extra is Map<String, dynamic>) {
                tx = extra['transaction'] as TransactionModel?;
                id = extra['id'] as String? ?? tx?.id;
              }
              return TransactionDetailScreen(
                transaction: tx,
                transactionId: id,
              );
            },
          ),
        ],
      ),
    ],

    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Route not found: ${state.uri.toString()}'),
      ),
    ),
  );
}

/// Provider for GoRouter throughout the application
final routerProvider = Provider<GoRouter>((ref) {
  return createAppRouter();
});
