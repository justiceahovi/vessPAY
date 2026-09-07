import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api/api_error.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/vesspay_text_field.dart';
import '../../auth/models/user_model.dart';
import '../../auth/repositories/auth_repository.dart';
import '../../kyc/providers/kyc_providers.dart';
import 'profile_screen.dart';

/// Lets a user edit their own name, country, and nationality.
///
/// Country/nationality become read-only once identity verification is
/// approved, mirroring the backend's `KYC_LOCKED` rule (`PUT /api/auth/me`):
/// those fields must not silently diverge from what WeWire has verified.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _countryController = TextEditingController();
  final _nationalityController = TextEditingController();

  bool _initialized = false;
  bool _isSaving = false;
  String? _serverErrorMessage;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _countryController.dispose();
    _nationalityController.dispose();
    super.dispose();
  }

  void _initializeFrom(UserModel user) {
    if (_initialized) return;
    _firstNameController.text = user.firstName;
    _lastNameController.text = user.lastName;
    _countryController.text = user.country ?? '';
    _nationalityController.text = user.nationality ?? '';
    _initialized = true;
  }

  Future<void> _handleSave({required bool identityLocked}) async {
    setState(() => _serverErrorMessage = null);

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      await ref.read(authRepositoryProvider).updateProfile(
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            country: identityLocked ? null : _countryController.text.trim(),
            nationality:
                identityLocked ? null : _nationalityController.text.trim(),
          );

      ref.invalidate(profileUserProvider);

      if (!mounted) return;
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() {
        _serverErrorMessage =
            e.message.isNotEmpty ? e.message : 'Failed to update profile.';
      });
    } catch (_) {
      setState(() {
        _serverErrorMessage = 'An unexpected error occurred. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(profileUserProvider);
    final kycAsync = ref.watch(kycStatusProvider);
    final identityLocked = kycAsync.valueOrNull?.isApproved ?? false;

    final user = userAsync.valueOrNull;
    if (user != null) _initializeFrom(user);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        elevation: 0,
        title: Text(
          'Edit Profile',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
      ),
      body: SafeArea(
        child: userAsync.isLoading && user == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_serverErrorMessage != null) ...[
                        Container(
                          key: const Key('edit_profile_error_banner'),
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

                      Row(
                        children: [
                          Expanded(
                            child: VessPayTextField(
                              fieldKey: const Key('edit_profile_first_name_field'),
                              label: 'First name',
                              controller: _firstNameController,
                              enabled: !_isSaving,
                              validator: (val) => (val == null || val.trim().isEmpty)
                                  ? 'First name is required'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: VessPayTextField(
                              fieldKey: const Key('edit_profile_last_name_field'),
                              label: 'Last name',
                              controller: _lastNameController,
                              enabled: !_isSaving,
                              validator: (val) => (val == null || val.trim().isEmpty)
                                  ? 'Last name is required'
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      VessPayTextField(
                        fieldKey: const Key('edit_profile_country_field'),
                        label: 'Country of residence',
                        controller: _countryController,
                        enabled: !_isSaving,
                        readOnly: identityLocked,
                      ),
                      const SizedBox(height: 16),

                      VessPayTextField(
                        fieldKey: const Key('edit_profile_nationality_field'),
                        label: 'Nationality',
                        controller: _nationalityController,
                        enabled: !_isSaving,
                        readOnly: identityLocked,
                      ),

                      if (identityLocked) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Locked after identity verification. Contact support if these are incorrect.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                            height: 1.3,
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),

                      ElevatedButton(
                        key: const Key('edit_profile_save_button'),
                        onPressed: _isSaving
                            ? null
                            : () => _handleSave(identityLocked: identityLocked),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text('Save Changes'),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
