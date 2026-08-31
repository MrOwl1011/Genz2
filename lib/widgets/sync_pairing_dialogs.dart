import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, FilteringTextInputFormatter;
import 'package:google_fonts/google_fonts.dart';

import '../providers/auth_provider.dart';
import '../services/backend_api_service.dart' show BackendPairingCode;
import '../theme/app_colors.dart';
import 'dialog_buttons.dart';

/// Shared multi-device sync pairing dialogs — shown from both More →
/// Settings and the "Who's Watching?" profile picker, so a device can be
/// linked into an existing account's sync group either place. Kept in one
/// file rather than duplicated per screen.

Future<void> showPairingCodeDialog(
  BuildContext context, {
  required AuthProvider authProvider,
  required bool isArabic,
}) {
  return showDialog(
    context: context,
    builder: (_) => PairingCodeDialog(authProvider: authProvider, isArabic: isArabic),
  );
}

Future<void> showJoinCodeDialog(
  BuildContext context, {
  required AuthProvider authProvider,
  required bool isArabic,
}) {
  return showDialog(
    context: context,
    builder: (_) => JoinCodeDialog(authProvider: authProvider, isArabic: isArabic),
  );
}

/// "Show my sync code" dialog — requests a pairing code from the backend and
/// displays it with a live countdown until it expires. See
/// AuthProvider.createSyncPairingCode's doc comment for why a null result
/// (backend unreachable, or this device never registered) is not an error.
class PairingCodeDialog extends StatefulWidget {
  final AuthProvider authProvider;
  final bool isArabic;

  const PairingCodeDialog({super.key, required this.authProvider, required this.isArabic});

  @override
  State<PairingCodeDialog> createState() => _PairingCodeDialogState();
}

class _PairingCodeDialogState extends State<PairingCodeDialog> {
  BackendPairingCode? _pairingCode;
  bool _loading = true;
  bool _failed = false;
  Timer? _ticker;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await widget.authProvider.createSyncPairingCode();
    if (!mounted) return;
    if (result == null) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    setState(() {
      _pairingCode = result;
      _loading = false;
      _remaining = result.expiresAt.difference(DateTime.now().toUtc());
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final code = _pairingCode;
      if (code == null || !mounted) return;
      final left = code.expiresAt.difference(DateTime.now().toUtc());
      if (left.isNegative) {
        _ticker?.cancel();
      }
      setState(() => _remaining = left.isNegative ? Duration.zero : left);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isArabic = widget.isArabic;
    final minutes = _remaining.inMinutes;
    final seconds = _remaining.inSeconds % 60;

    return AlertDialog(
      backgroundColor: colors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        isArabic ? 'رمز المزامنة' : 'Sync Code',
        style: GoogleFonts.outfit(color: colors.ink, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 280,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            : _failed
            ? Text(
                isArabic
                    ? 'تعذر إنشاء رمز الآن. تحقق من اتصالك وحاول مرة أخرى.'
                    : 'Could not create a code right now. Check your connection and try again.',
                style: GoogleFonts.outfit(color: colors.ink.withValues(alpha: 0.7)),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isArabic
                        ? 'أدخل هذا الرمز في الجهاز الآخر لربطه بحسابك'
                        : 'Enter this code on your other device to link it',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: colors.ink.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: () {
                      final code = _pairingCode?.code;
                      if (code == null) return;
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isArabic ? 'تم النسخ' : 'Copied'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: colors.ink.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: colors.ink.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _pairingCode!.code,
                            style: GoogleFonts.outfit(
                              color: colors.ink,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 8,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.copy_rounded,
                            color: colors.ink.withValues(alpha: 0.5),
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _remaining > Duration.zero
                        ? (isArabic
                              ? 'ينتهي خلال $minutes:${seconds.toString().padLeft(2, '0')}'
                              : 'Expires in $minutes:${seconds.toString().padLeft(2, '0')}')
                        : (isArabic ? 'انتهت صلاحية الرمز' : 'Code expired'),
                    style: GoogleFonts.outfit(
                      color: _remaining > Duration.zero ? colors.ink.withValues(alpha: 0.5) : colors.error,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        DialogPrimaryButton(
          label: isArabic ? 'تم' : 'Done',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// "Enter a code" dialog — joins the backend account a pairing code (minted
/// by another device via [PairingCodeDialog]) was issued for. See
/// AuthProvider.joinSyncAccount's doc comment for the local-data caveat.
class JoinCodeDialog extends StatefulWidget {
  final AuthProvider authProvider;
  final bool isArabic;

  const JoinCodeDialog({super.key, required this.authProvider, required this.isArabic});

  @override
  State<JoinCodeDialog> createState() => _JoinCodeDialogState();
}

class _JoinCodeDialogState extends State<JoinCodeDialog> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    final isArabic = widget.isArabic;
    if (code.isEmpty) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final errorMessage = await widget.authProvider.joinSyncAccount(code);
    if (!mounted) return;
    if (errorMessage == null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isArabic ? 'تم الربط بنجاح' : 'Linked successfully'),
        ),
      );
    } else {
      setState(() {
        _submitting = false;
        _error = errorMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isArabic = widget.isArabic;

    return AlertDialog(
      backgroundColor: colors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        isArabic ? 'إدخال رمز المزامنة' : 'Enter Sync Code',
        style: GoogleFonts.outfit(color: colors.ink, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isArabic
                  ? 'أدخل الرمز الظاهر على الجهاز الآخر'
                  : 'Enter the code shown on your other device',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: colors.ink.withValues(alpha: 0.7), fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 4,
              style: GoogleFonts.outfit(
                color: colors.ink,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
              ),
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: colors.ink.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(color: colors.error, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        DialogSecondaryButton(
          label: isArabic ? 'إلغاء' : 'Cancel',
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        ),
        DialogPrimaryButton(
          label: _submitting
              ? (isArabic ? 'جارٍ الربط...' : 'Linking...')
              : (isArabic ? 'ربط' : 'Link'),
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}
