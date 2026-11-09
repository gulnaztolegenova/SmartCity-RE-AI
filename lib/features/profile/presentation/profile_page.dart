import '../../../core/widgets/aligned_panel_grid.dart';
import '../../../core/widgets/adaptive_metric_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_city_renewable_ai/l10n/app_localizations.dart';

import '../../../app/localization/locale_controller.dart';
import '../../../core/extensions/async_value_x.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_confirmation_dialog.dart';
import '../../../core/widgets/app_fields.dart';
import '../../../core/widgets/metric_tile.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/models/user_profile.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _organizationController = TextEditingController();
  final _cityController = TextEditingController();

  String? _seededUid;
  String _languageCode = 'kk';
  String? _defaultSiteId;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _organizationController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  void _seed(UserProfile? profile) {
    if (profile == null || _seededUid == profile.uid) {
      return;
    }
    _seededUid = profile.uid;
    _fullNameController.text = profile.fullName;
    _emailController.text = profile.backupEmail ?? '';
    _organizationController.text = profile.organization ?? '';
    _cityController.text = profile.city;
    _languageCode = profile.preferredLanguageCode;
    _defaultSiteId = profile.defaultSiteId;
  }

  Future<void> _save(UserProfile profile) async {
    final l10n = AppLocalizations.of(context);
    try {
      final normalizedEmail = _normalizeNullable(_emailController.text);
      final normalizedOrganization = _normalizeNullable(
        _organizationController.text,
      );
      final updated = profile.copyWith(
        fullName: _fullNameController.text.trim(),
        backupEmail: normalizedEmail,
        organization: normalizedOrganization,
        city: _cityController.text.trim(),
        preferredLanguageCode: _languageCode,
        defaultSiteId: _defaultSiteId,
      );
      final nothingChanged =
          updated.fullName == profile.fullName &&
          updated.city == profile.city &&
          updated.preferredLanguageCode == profile.preferredLanguageCode &&
          _normalizeNullable(profile.backupEmail) == normalizedEmail &&
          _normalizeNullable(profile.organization) == normalizedOrganization &&
          updated.defaultSiteId == profile.defaultSiteId;
      if (!nothingChanged) {
        await ref.read(firestoreRepositoryProvider).saveUserProfile(updated);
      }
      await ref
          .read(localeControllerProvider.notifier)
          .setLocale(Locale(_languageCode));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.profileSaved),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.profileSaveError),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  String? _normalizeNullable(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  Future<void> _confirmSignOut() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showAppConfirmationDialog(
      context: context,
      title: l10n.signOutConfirmTitle,
      message: l10n.signOutConfirmMessage,
      confirmLabel: l10n.signOutConfirmAction,
      cancelLabel: l10n.signOutStay,
      icon: Icons.logout_rounded,
      accentColor: Theme.of(context).colorScheme.error,
    );
    if (!confirmed) {
      return;
    }
    await ref.read(phoneAuthServiceProvider).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final user = ref.watch(firebaseUserProvider).valueOrNull;
    final sites = ref.watch(currentUserSitesProvider).valueOrNull ?? const [];
    final healthAsync = ref.watch(serverHealthProvider);
    final metaAsync = ref.watch(forecastMetaProvider);
    _seed(profile);

    if (profile == null || user == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final status = healthAsync.maybeWhen(
      data: (value) => value['status']?.toString() ?? 'unknown',
      orElse: () => 'unknown',
    );
    final summaryCard = AppCard(
      animated: true,
      child: _ResponsiveMetricGrid(
        maxColumns: 4,
        children: [
          MetricTile(
            label: l10n.accountUid,
            value: user.uid.substring(0, 8),
            icon: Icons.badge_outlined,
          ),
          MetricTile(
            label: l10n.signedInPhone,
            value: formatPhoneDisplay(profile.phoneNumber),
            icon: Icons.phone_rounded,
          ),
          MetricTile(
            label: l10n.defaultSite,
            value: _defaultSiteName(sites, profile, l10n),
            icon: Icons.solar_power_rounded,
          ),
          MetricTile(
            label: l10n.preferredLanguage,
            value: _languageCode.toUpperCase(),
            icon: Icons.translate_rounded,
          ),
        ],
      ),
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCard(
            animated: true,
            child: SectionHeader(
              title: l10n.profileTitle,
              subtitle: l10n.profileSubtitle,
              trailing: AppPrimaryButton(
                label: l10n.save,
                icon: const Icon(Icons.save_outlined),
                onPressed: () => _save(profile),
              ),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final account = AppCard(
                animated: true,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionHeader(
                        title: l10n.accountSection,
                        subtitle: l10n.userOnlyWorkspace,
                      ),
                      const SizedBox(height: 18),
                      AppTextField(
                        controller: _fullNameController,
                        label: l10n.fullName,
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        enabled: false,
                        initialValue: formatPhoneDisplay(profile.phoneNumber),
                        label: l10n.signedInPhone,
                        prefixIcon: const Icon(Icons.phone_rounded),
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        controller: _emailController,
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
                      AppTextField(
                        controller: _cityController,
                        label: l10n.city,
                        prefixIcon: const Icon(Icons.location_city_rounded),
                      ),
                    ],
                  ),
                ),
              );
              final settings = AppCard(
                animated: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(
                      title: l10n.localeSection,
                      subtitle: l10n.sitePreferences,
                    ),
                    const SizedBox(height: 18),
                    AppDropdownMenuField<String>(
                      label: l10n.preferredLanguage,
                      selectedValue: _languageCode,
                      prefixIcon: const Icon(Icons.language_rounded),
                      options: [
                        AppDropdownOption(
                          value: 'kk',
                          label: l10n.languageKazakh,
                        ),
                        AppDropdownOption(
                          value: 'ru',
                          label: l10n.languageRussian,
                        ),
                        AppDropdownOption(
                          value: 'en',
                          label: l10n.languageEnglish,
                        ),
                      ],
                      onSelected: (value) {
                        if (value != null) {
                          setState(() => _languageCode = value);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    AppDropdownMenuField<String>(
                      label: l10n.defaultSite,
                      selectedValue:
                          _defaultSiteId ??
                          (sites.isNotEmpty ? sites.first.id : null),
                      prefixIcon: const Icon(Icons.location_on_outlined),
                      enabled: sites.isNotEmpty,
                      options: [
                        for (final site in sites)
                          AppDropdownOption(value: site.id, label: site.name),
                      ],
                      onSelected: sites.isEmpty
                          ? null
                          : (value) {
                              setState(() => _defaultSiteId = value);
                            },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: AppSecondaryButton(
                        label: l10n.signOut,
                        icon: const Icon(Icons.logout_rounded),
                        onPressed: _confirmSignOut,
                      ),
                    ),
                  ],
                ),
              );
              final server = AppCard(
                animated: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(
                      title: l10n.connectedServer,
                      subtitle: l10n.systemStatus,
                    ),
                    const SizedBox(height: 18),
                    _ResponsiveMetricGrid(
                      maxColumns: 2,
                      children: [
                        MetricTile(
                          label: l10n.healthStatus,
                          value: status,
                          icon: status == 'ok'
                              ? Icons.cloud_done_rounded
                              : Icons.cloud_off_rounded,
                          color: status == 'ok'
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.error,
                        ),
                        MetricTile(
                          label: l10n.modelVersion,
                          value: metaAsync.maybeWhen(
                            data: (value) =>
                                '${value['model_name'] ?? l10n.unknown} / ${value['model_version'] ?? l10n.unknown}\n${value['quality_model'] ?? ''}',
                            orElse: () => l10n.unknown,
                          ),
                          icon: Icons.model_training_outlined,
                        ),
                      ],
                    ),
                  ],
                ),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AlignedPanelGrid(
                    key: const ValueKey('profile-settings-row'),
                    children: [account, settings],
                  ),
                  const SizedBox(height: 16),
                  server,
                  const SizedBox(height: 16),
                  summaryCard,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _defaultSiteName(
    List<dynamic> sites,
    UserProfile profile,
    AppLocalizations l10n,
  ) {
    if (sites.isEmpty) {
      return l10n.noSiteTitle;
    }
    final wantedId = _defaultSiteId ?? profile.defaultSiteId;
    for (final site in sites) {
      if (site.id == wantedId) {
        return site.name;
      }
    }
    return sites.first.name;
  }
}

class _ResponsiveMetricGrid extends StatelessWidget {
  const _ResponsiveMetricGrid({required this.children, this.maxColumns = 4});
  final List<Widget> children;
  final int maxColumns;
  @override
  Widget build(BuildContext context) =>
      AdaptiveMetricGrid(maxColumns: maxColumns, children: children);
}
