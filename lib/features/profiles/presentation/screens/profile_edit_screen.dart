import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../providers/user_prefs_provider.dart';
import '../../../../theme/app_colors.dart';
import '../../../../widgets/dialog_buttons.dart';
import '../../domain/entities/profile_entity.dart';
import '../providers/profile_provider.dart';
import '../widgets/profile_avatar_tile.dart';

/// Create/edit form for a single profile. [existingProfile] null means
/// "create"; non-null means "edit" (and shows a Delete action).
class ProfileEditScreen extends StatefulWidget {
  final ProfileEntity? existingProfile;

  const ProfileEditScreen({super.key, this.existingProfile});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final TextEditingController _nameController;
  late String _selectedAvatar;
  bool _isSaving = false;

  bool get _isEditing => widget.existingProfile != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.existingProfile?.name ?? '',
    );
    _selectedAvatar = widget.existingProfile?.avatar ?? kAvatarColorKeys.first;
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    final colors = context.colors;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: colors.error,
        content: Text(message, style: GoogleFonts.archivo(color: Colors.white)),
      ),
    );
  }

  Future<void> _save() async {
    final isArabic = context.read<UserPrefsProvider>().locale == 'ar';
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError(isArabic ? 'الرجاء إدخال اسم.' : 'Please enter a name.');
      return;
    }

    setState(() => _isSaving = true);
    final provider = context.read<ProfileProvider>();
    final success = _isEditing
        ? await provider.updateProfile(
            widget.existingProfile!.profileId,
            name: name,
            avatar: _selectedAvatar,
          )
        : await provider.createProfile(name: name, avatar: _selectedAvatar);

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (success) {
      Navigator.of(context).pop();
    } else {
      _showError(
        provider.errorMessage ??
            (isArabic ? 'حدث خطأ ما.' : 'Something went wrong.'),
      );
    }
  }

  Future<void> _delete() async {
    final colors = context.colors;
    final isArabic = context.read<UserPrefsProvider>().locale == 'ar';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isArabic ? 'حذف الملف الشخصي؟' : 'Delete Profile?',
          style: GoogleFonts.archivo(
            color: colors.ink,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          isArabic
              ? 'سيؤدي هذا إلى إزالة "${widget.existingProfile!.name}" من هذا الحساب.'
              : 'This removes "${widget.existingProfile!.name}" from this account.',
          style: GoogleFonts.archivo(color: colors.ink.withValues(alpha: 0.7)),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          DialogSecondaryButton(
            label: isArabic ? 'إلغاء' : 'Cancel',
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          DialogPrimaryButton(
            label: isArabic ? 'حذف' : 'Delete',
            color: colors.error,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    final provider = context.read<ProfileProvider>();
    final wasActive =
        provider.activeProfile?.profileId == widget.existingProfile!.profileId;
    final success = await provider.deleteProfile(
      widget.existingProfile!.profileId,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (success) {
      if (wasActive) {
        // Deleting the profile you're currently viewing as clears
        // ProfileProvider.activeProfile, which AppRoot reacts to by
        // swapping the app's root content back to the profile picker — that
        // already tears down and rebuilds everything above it (this screen,
        // and whatever picker screen is under it), so a plain pop() here
        // would be racing that root-level swap. Unwind everything pushed on
        // top of the root in one step instead and let the root's own
        // rebuild take it from there.
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        Navigator.of(context).pop();
      }
    } else {
      _showError(
        provider.errorMessage ??
            (isArabic ? 'حدث خطأ ما.' : 'Something went wrong.'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isArabic = context.watch<UserPrefsProvider>().locale == 'ar';

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors.backgroundGradient,
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: colors.ink,
                      ),
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        _isEditing
                            ? (isArabic ? 'تعديل الملف الشخصي' : 'EDIT PROFILE')
                            : (isArabic ? 'إضافة ملف شخصي' : 'ADD PROFILE'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.archivo(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          color: colors.ink,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  child: Column(
                    children: [
                      ProfileAvatarTile(
                        previewAvatarKey: _selectedAvatar,
                        previewName: _nameController.text,
                        size: 110,
                        showLabel: false,
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        controller: _nameController,
                        maxLength: 60,
                        textCapitalization: TextCapitalization.words,
                        style: GoogleFonts.archivo(
                          color: colors.ink,
                          fontSize: 16,
                        ),
                        decoration: InputDecoration(
                          labelText: isArabic ? 'الاسم' : 'Name',
                          labelStyle: GoogleFonts.archivo(
                            color: colors.ink.withValues(alpha: 0.6),
                          ),
                          filled: true,
                          fillColor: colors.surface,
                          counterStyle: GoogleFonts.archivo(
                            color: colors.ink.withValues(alpha: 0.4),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: colors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: colors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: colors.brandPrimary,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          isArabic ? 'لون الصورة الرمزية' : 'Avatar Color',
                          style: GoogleFonts.archivo(
                            color: colors.ink.withValues(alpha: 0.7),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 14,
                        runSpacing: 14,
                        alignment: WrapAlignment.center,
                        children: [
                          for (final key in kAvatarColorKeys)
                            ProfileAvatarTile(
                              previewAvatarKey: key,
                              previewName: _nameController.text,
                              size: 48,
                              showLabel: false,
                              selected: _selectedAvatar == key,
                              onTap: () =>
                                  setState(() => _selectedAvatar = key),
                            ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.brandPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : Text(
                                  _isEditing
                                      ? (isArabic
                                            ? 'حفظ التغييرات'
                                            : 'Save Changes')
                                      : (isArabic
                                            ? 'إنشاء ملف شخصي'
                                            : 'Create Profile'),
                                  style: GoogleFonts.archivo(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                      ),
                      if (_isEditing) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton(
                            onPressed: _isSaving ? null : _delete,
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: colors.error.withValues(alpha: 0.5),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              isArabic ? 'حذف الملف الشخصي' : 'Delete Profile',
                              style: GoogleFonts.archivo(
                                color: colors.error,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
