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

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _countryController = TextEditingController(text: 'United Kingdom');
  final _nationalityController = TextEditingController(text: 'British');

  bool _isLoading = false;
  String? _serverErrorMessage;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _countryController.dispose();
    _nationalityController.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
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

      await authRepo.register(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        country: _countryController.text.trim().isNotEmpty
            ? _countryController.text.trim()
            : null,
        nationality: _nationalityController.text.trim().isNotEmpty
            ? _nationalityController.text.trim()
            : null,
      );

      // A brand new account has no destination or wallet currency yet; drop
      // anything cached from a previous session on this device so setup starts clean.
      ref.read(currentTravelProfileProvider.notifier).clear();
      await ref.read(walletCurrencyProvider.notifier).clear();

      if (!mounted) return;

      // First run: pick the wallet currency, then continue to travel-mode-setup
      context.go(AppRoutes.walletCurrencySetup);
    } on ApiException catch (e) {
      setState(() {
        _serverErrorMessage = e.message.isNotEmpty
            ? e.message
            : 'Registration failed. Please check your details and try again.';
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
                const SizedBox(height: 28),
                // Display Title & Subtitle per DESIGN.md
                Text(
                  'Create your account',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontSize: 30,
                        fontWeight: FontWeight.w400,
                        letterSpacing: -0.5,
                        color: AppColors.ink,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start paying across Africa in seconds from your travel wallet.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.muted,
                        height: 1.4,
                      ),
                ),
                const SizedBox(height: 24),

                // Server Error Banner
                if (_serverErrorMessage != null) ...[
                  Container(
                    key: const Key('signup_error_banner'),
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

                // First Name & Last Name Row
                Row(
                  children: [
                    Expanded(
                      child: VessPayTextField(
                        fieldKey: const Key('signup_first_name_field'),
                        label: 'First name',
                        hintText: 'Alex',
                        controller: _firstNameController,
                        enabled: !_isLoading,
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'First name is required';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: VessPayTextField(
                        fieldKey: const Key('signup_last_name_field'),
                        label: 'Last name',
                        hintText: 'Johnson',
                        controller: _lastNameController,
                        enabled: !_isLoading,
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Last name is required';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Email Field
                VessPayTextField(
                  fieldKey: const Key('signup_email_field'),
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
                const SizedBox(height: 16),

                // Password Field
                VessPayTextField(
                  fieldKey: const Key('signup_password_field'),
                  label: 'Password',
                  hintText: 'At least 6 characters',
                  controller: _passwordController,
                  isPassword: true,
                  enabled: !_isLoading,
                  validator: (val) {
                    if (val == null || val.isEmpty) {
                      return 'Password is required';
                    }
                    if (val.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Country of Residence
                VessPayTextField(
                  fieldKey: const Key('signup_country_field'),
                  label: 'Country of residence',
                  hintText: 'United Kingdom',
                  controller: _countryController,
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 16),

                // Nationality
                VessPayTextField(
                  fieldKey: const Key('signup_nationality_field'),
                  label: 'Nationality',
                  hintText: 'British',
                  controller: _nationalityController,
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 32),

                // Submit Button
                ElevatedButton(
                  key: const Key('signup_submit_button'),
                  onPressed: _isLoading ? null : _handleSignup,
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
                      : const Text('Create Account'),
                ),
                const SizedBox(height: 20),

                // Switch to Log In
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'Already have an account? ',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.muted,
                      ),
                    ),
                    GestureDetector(
                      key: const Key('signup_to_login_link'),
                      onTap: _isLoading
                          ? null
                          : () => context.go(AppRoutes.login),
                      child: const Text(
                        'Sign In',
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
