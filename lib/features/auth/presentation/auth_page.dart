import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:smart_city_renewable_ai/l10n/app_localizations.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/auth_hard_refresh.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_fields.dart';
import '../../../data/services/firebase_phone_auth_service.dart';
import 'widgets/auth_stage_scaffold.dart';
import 'widgets/otp_code_field.dart';

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  final _phoneController = TextEditingController();

  bool _otpRequested = false;
  bool _loading = false;
  bool _otpHasError = false;
  String? _lastSubmittedOtp;

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(_handlePhoneChanged);
  }

  @override
  void dispose() {
    _phoneController.removeListener(_handlePhoneChanged);
    _phoneController.dispose();
    super.dispose();
  }

  FirebasePhoneAuthService get _authService =>
      ref.read(phoneAuthServiceProvider);

  bool get _phoneValid => isKazakhPhoneValid(_phoneController.text);

  void _handlePhoneChanged() {
    if (!mounted || _otpRequested) {
      return;
    }
    setState(() {});
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _requestOtp() async {
    final l10n = AppLocalizations.of(context);
    final rawPhone = _phoneController.text.trim();
    if (!isKazakhPhoneValid(rawPhone)) {
      _snack(l10n.authInvalidPhone, error: true);
      return;
    }

    setState(() {
      _loading = true;
      _otpHasError = false;
      _lastSubmittedOtp = null;
    });

    try {
      await _authService.requestOtp(
        phoneNumber: normalizeKazakhPhone(rawPhone),
      );
      if (!mounted) {
        return;
      }
      setState(() => _otpRequested = true);
      _snack(l10n.authOtpSent);
    } catch (_) {
      _snack(l10n.authErrorSendCode, error: true);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _verifyOtp(String code) async {
    final l10n = AppLocalizations.of(context);
    if (code.length != 6) {
      _snack(l10n.authCodeHint, error: true);
      return;
    }

    setState(() {
      _loading = true;
      _otpHasError = false;
      _lastSubmittedOtp = code;
    });

    try {
      await _authService.verifyOtp(smsCode: code);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _otpHasError = true;
        _lastSubmittedOtp = null;
      });
      _snack(l10n.authErrorVerify, error: true);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _resetOtpStep() {
    setState(() {
      _otpRequested = false;
      _otpHasError = false;
      _lastSubmittedOtp = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = _otpRequested ? l10n.authOtpTitle : l10n.authTitle;
    final description = _otpRequested
        ? l10n.authOtpSubtitle(formatPhoneDisplay(_phoneController.text))
        : l10n.authPhoneEntryDescription;

    return AuthStageScaffold(
      maxWidth: 640,
      onRefresh: performAuthHardRefresh,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: AppCard(
            padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).width < 760 ? 18 : 34,
            ),
            color: Colors.white.withValues(alpha: 0.96),
            animated: true,
            child: AnimatedSize(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AuthHeader(
                    title: title,
                    description: description,
                    isOtpStep: _otpRequested,
                  ),
                  const SizedBox(height: 28),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.045),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: _otpRequested
                        ? _OtpStep(
                            key: const ValueKey('otp-step'),
                            phoneNumber: formatPhoneDisplay(
                              _phoneController.text,
                            ),
                            isLoading: _loading,
                            hasError: _otpHasError,
                            codeSentLabel: l10n.authCodeSentBadge,
                            changePhoneLabel: l10n.authChangePhone,
                            hint: l10n.authAutoVerifyHint,
                            verifyingLabel: l10n.authVerifyingCode,
                            onChanged: (value) {
                              setState(() {
                                if (value.length < 6) {
                                  _lastSubmittedOtp = null;
                                }
                                if (_otpHasError && value.length < 6) {
                                  _otpHasError = false;
                                }
                              });
                            },
                            onCompleted: (value) {
                              if (_lastSubmittedOtp == value || _loading) {
                                return;
                              }
                              _verifyOtp(value);
                            },
                            onChangePhone: _resetOtpStep,
                          )
                        : _PhoneStep(
                            key: const ValueKey('phone-step'),
                            controller: _phoneController,
                            isLoading: _loading,
                            phoneLabel: l10n.authPhoneLabel,
                            phoneHint: l10n.authPhoneHint,
                            sendCodeLabel: l10n.authSendCode,
                            onPressed: _phoneValid ? _requestOtp : null,
                          ),
                  ),
                  if (_otpHasError) ...[
                    const SizedBox(height: 18),
                    _AuthErrorBanner(message: l10n.authErrorVerify),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthHeader extends StatelessWidget {
  const _AuthHeader({
    required this.title,
    required this.description,
    required this.isOtpStep,
  });

  final String title;
  final String description;
  final bool isOtpStep;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w900,
            fontSize: MediaQuery.sizeOf(context).width < 760 ? 28 : 34,
            letterSpacing: -1.1,
            height: 1.08,
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Text(
            description,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.58,
            ),
          ),
        ),
      ],
    );
  }
}

class _PhoneStep extends StatelessWidget {
  const _PhoneStep({
    required this.controller,
    required this.isLoading,
    required this.phoneLabel,
    required this.phoneHint,
    required this.sendCodeLabel,
    required this.onPressed,
    super.key,
  });

  final TextEditingController controller;
  final bool isLoading;
  final String phoneLabel;
  final String phoneHint;
  final String sendCodeLabel;
  final Future<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppPhoneField(
                controller: controller,
                label: phoneLabel,
                hint: phoneHint,
              ),
              const SizedBox(height: 18),
              AppPrimaryButton(
                label: sendCodeLabel,
                isLoading: isLoading,
                onPressed: onPressed,
                icon: Icon(PhosphorIcons.paperPlaneTilt()),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OtpStep extends StatelessWidget {
  const _OtpStep({
    required this.phoneNumber,
    required this.isLoading,
    required this.hasError,
    required this.codeSentLabel,
    required this.changePhoneLabel,
    required this.hint,
    required this.verifyingLabel,
    required this.onChanged,
    required this.onCompleted,
    required this.onChangePhone,
    super.key,
  });

  final String phoneNumber;
  final bool isLoading;
  final bool hasError;
  final String codeSentLabel;
  final String changePhoneLabel;
  final String hint;
  final String verifyingLabel;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onCompleted;
  final VoidCallback onChangePhone;

  @override
  Widget build(BuildContext context) {
    return _StepPanel(
      key: key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            runAlignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatusPill(
                label: codeSentLabel,
                icon: PhosphorIcons.checkCircle(),
              ),
              _PhonePill(phoneNumber: phoneNumber),
            ],
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: isLoading ? null : onChangePhone,
            child: Text(changePhoneLabel),
          ),
          const SizedBox(height: 10),
          OtpCodeField(
            enabled: !isLoading,
            hasError: hasError,
            onChanged: onChanged,
            onCompleted: onCompleted,
          ),
          const SizedBox(height: 16),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.55,
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: isLoading
                ? Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: _VerifyingChip(label: verifyingLabel),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _StepPanel extends StatelessWidget {
  const _StepPanel({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: key,
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 760 ? 16 : 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.92),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F141F52),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFFAF5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD3F0E2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF1B8B5E)),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: const Color(0xFF1B8B5E),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhonePill extends StatelessWidget {
  const _PhonePill({required this.phoneNumber});

  final String phoneNumber;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.9),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            PhosphorIcons.deviceMobile(),
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            phoneNumber,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _VerifyingChip extends StatelessWidget {
  const _VerifyingChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.9),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}

class _AuthErrorBanner extends StatelessWidget {
  const _AuthErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
