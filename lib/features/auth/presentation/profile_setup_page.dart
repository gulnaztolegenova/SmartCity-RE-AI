import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_city_renewable_ai/l10n/app_localizations.dart';

import '../../../app/localization/locale_controller.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/async_value_x.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/auth_hard_refresh.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_fields.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/models/user_profile.dart';
import 'widgets/auth_stage_scaffold.dart';

class ProfileSetupPage extends ConsumerStatefulWidget {
  const ProfileSetupPage({super.key});

  @override
  ConsumerState<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends ConsumerState<ProfileSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _organizationController = TextEditingController();

  bool _saving = false;
  bool _seededFromProfile = false;
  String _languageCode = AppConstants.defaultLanguageCode;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _organizationController.dispose();
    super.dispose();
  }

  void _seedFromProfile(UserProfile? profile) {
    if (_seededFromProfile) {
      return;
    }
    _fullNameController.text = profile?.fullName ?? '';
    _emailController.text = profile?.backupEmail ?? '';
    _organizationController.text = profile?.organization ?? '';
    _languageCode =
        profile?.preferredLanguageCode ??
        ref.read(localeControllerProvider).languageCode;
    _seededFromProfile = true;
  }

  String? _validateRequired(String? value, AppLocalizations l10n) {
    if (value == null || value.trim().isEmpty) {
      return l10n.requiredField;
    }
    return null;
  }

  String? _validateEmail(String? value, AppLocalizations l10n) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());
    return ok ? null : l10n.invalidEmail;
  }

  Future<void> _save(User user, UserProfile? profile) async {
    final l10n = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(firestoreRepositoryProvider);
      final userProfile = UserProfile(
        uid: user.uid,
        fullName: _fullNameController.text.trim(),
        phoneNumber: user.phoneNumber ?? profile?.phoneNumber ?? '',
        city: profile?.city ?? AppConstants.defaultCity,
        preferredLanguageCode: _languageCode,
        backupEmail: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        organization: _organizationController.text.trim().isEmpty
            ? null
            : _organizationController.text.trim(),
        defaultSiteId: profile?.defaultSiteId,
        createdAt: profile?.createdAt,
        updatedAt: profile?.updatedAt,
      );

      await repo.saveUserProfile(userProfile);
      await ref
          .read(localeControllerProvider.notifier)
          .setLocale(Locale(_languageCode));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.onboardingSuccess),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.go('/sites');
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.onboardingSaveError),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(firebaseUserProvider).valueOrNull;
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    _seedFromProfile(profile);

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return AuthStageScaffold(
      maxWidth: 760,
      onRefresh: performAuthHardRefresh,
      child: _buildFormCard(l10n, user, profile),
    );
  }

  Widget _buildFormCard(
    AppLocalizations l10n,
    User user,
    UserProfile? profile,
  ) {
    return AppCard(
      animated: true,
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 760 ? 22 : 30),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: l10n.onboardingTitle,
              subtitle: l10n.onboardingSubtitle,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _InfoPill(
                  icon: Icons.phone_rounded,
                  label: formatPhoneDisplay(user.phoneNumber ?? ''),
                ),
                _InfoPill(icon: Icons.map_outlined, label: l10n.goToSites),
              ],
            ),
            const SizedBox(height: 18),
            AppTextField(
              controller: _fullNameController,
              validator: (value) => _validateRequired(value, l10n),
              label: l10n.fullName,
              prefixIcon: const Icon(Icons.person_outline_rounded),
            ),
            const SizedBox(height: 14),
            AppTextField(
              initialValue: formatPhoneDisplay(user.phoneNumber ?? ''),
              label: l10n.phoneNumber,
              enabled: false,
              prefixIcon: const Icon(Icons.phone_rounded),
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _emailController,
              validator: (value) => _validateEmail(value, l10n),
              label: l10n.backupEmail,
              prefixIcon: const Icon(Icons.alternate_email_rounded),
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _organizationController,
              label: l10n.organization,
              prefixIcon: const Icon(Icons.apartment_rounded),
            ),
            const SizedBox(height: 14),
            AppDropdownMenuField<String>(
              label: l10n.preferredLanguage,
              selectedValue: _languageCode,
              prefixIcon: const Icon(Icons.language_rounded),
              options: [
                AppDropdownOption(value: 'kk', label: l10n.languageKazakh),
                AppDropdownOption(value: 'ru', label: l10n.languageRussian),
                AppDropdownOption(value: 'en', label: l10n.languageEnglish),
              ],
              onSelected: (value) {
                if (value != null) {
                  setState(() => _languageCode = value);
                }
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: AppPrimaryButton(
                label: l10n.completeRegistration,
                icon: const Icon(Icons.task_alt_rounded),
                isLoading: _saving,
                onPressed: () => _save(user, profile),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.9),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
