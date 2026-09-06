import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_error.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/vesspay_text_field.dart';
import '../../travel/providers/travel_providers.dart';
import '../../wallet/providers/currency_providers.dart';
import '../repositories/auth_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _serverErrorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    // Reset server error
    setState(() {
      _serverErrorMessage = null;
    });

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authRepo = ref.read(authRepositoryProvider);

      await authRepo.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      // Load the wallet currency and destination this user already has, so
      // returning users go straight to their dashboard instead of setting up again.
      final currency =
          await ref.read(walletCurrencyProvider.notifier).refresh();
      final profile =
          await ref.read(currentTravelProfileProvider.notifier).refresh();

      if (!mounted) return;

      final hasDestination =
          profile != null && profile.destinationCountry.isNotEmpty;

      if (currency == null || currency.isEmpty) {
        // Never chose a wallet currency: ask now, then resume where they left off.
        context.go(
          AppRoutes.walletCurrencySetup,
          extra: hasDestination ? AppRoutes.home : AppRoutes.travelModeSetup,
        );
        return;
      }

      context.go(hasDestination ? AppRoutes.home : AppRoutes.travelModeSetup);
    } on ApiException catch (e) {
      setState(() {
        _serverErrorMessage = e.message.isNotEmpty
            ? e.message
            : 'Login failed. Please check your credentials and try again.';
      });
    } catch (e) {
      setState(() {
        _serverErrorMessage = 'An unexpected error occurred. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                // Brand Mark & Wordmark Header
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceCard,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: const Icon(
                        Icons.blur_on_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'VessPay',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 36),
                // Display Title & Subtitle per DESIGN.md
                Text(
                  'Welcome back',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontSize: 30,
                        fontWeight: FontWeight.w400,
                        letterSpacing: -0.5,
                        color: AppColors.ink,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to access your VessPay wallet and travel corridors.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.muted,
                        height: 1.4,
                      ),
                ),
                const SizedBox(height: 28),

                // Server Error Banner
                if (_serverErrorMessage != null) ...[
                  Container(
                    key: const Key('login_error_banner'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 18,
                          color: AppColors.error,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _serverErrorMessage!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.error,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Email Field
                VessPayTextField(
                  fieldKey: const Key('login_email_field'),
                  label: 'Email address',
                  hintText: 'alex.johnson@example.com',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  enabled: !_isLoading,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Email is required';
                    }
                    if (!val.contains('@') || !val.contains('.')) {
                      return 'Enter a valid email address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),

                // Password Field
                VessPayTextField(
                  fieldKey: const Key('login_password_field'),
                  label: 'Password',
                  hintText: 'Your password',
                  controller: _passwordController,
                  isPassword: true,
                  enabled: !_isLoading,
                  validator: (val) {
                    if (val == null || val.isEmpty) {
                      return 'Password is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),

                // Submit Button
                ElevatedButton(
                  key: const Key('login_submit_button'),
                  onPressed: _isLoading ? null : _handleLogin,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Sign In'),
                ),
                const SizedBox(height: 24),

                // Switch to Sign Up
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      "Don't have an account? ",
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.muted,
                      ),
                    ),
                    GestureDetector(
                      key: const Key('login_to_signup_link'),
                      onTap: _isLoading
                          ? null
                          : () => context.go(AppRoutes.signup),
                      child: const Text(
                        'Create account',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
