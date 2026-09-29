import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';

/// Shared ID picker: large preview, validation state, and upload animation.
///
/// Lives in `core/widgets` because both roles submit an ID now - the technician
/// onboarding step and the client verification step render the identical
/// control. Duplicating it per feature is how the two would drift apart.
///
/// ## The three visual states
///
/// * **Empty** - a dashed-feel drop target inviting a camera or gallery pick.
/// * **Picked** - the actual image, full-bleed, with a "Tap to change" chip. A
///   file that failed validation is still shown, with a red border, so the
///   person can see what they chose next to the reason it was rejected.
/// * **Uploading** - the preview dims behind a progress ring and a status line,
///   because a silent several-second pause on a mobile connection reads as a
///   frozen app.
class IdDocumentPicker extends StatelessWidget {
  const IdDocumentPicker({
    super.key,
    required this.file,
    required this.onPicked,
    this.hasError = false,
    this.isUploading = false,
    this.uploadLabel = 'Uploading your ID...',
    this.emptyTitle = 'Tap to add your ID photo',
    this.emptySubtitle = 'Camera or gallery',
    this.height = 210,
  });

  final XFile? file;
  final ValueChanged<XFile> onPicked;
  final bool hasError;
  final bool isUploading;
  final String uploadLabel;
  final String emptyTitle;
  final String emptySubtitle;
  final double height;

  Future<void> _pick(BuildContext context, ImageSource source) async {
    try {
      final XFile? picked = await ImagePicker().pickImage(
        source: source,
        // Not downscaled hard: an ID has to stay legible for a reviewer,
        // unlike a job photo. Still capped so a 12 MP phone shot does not
        // blow the 5 MB bucket limit.
        maxWidth: 2400,
        imageQuality: 90,
      );
      // Null simply means the person backed out of the camera or picker. That
      // is not an error and must not raise anything.
      if (picked == null) return;
      onPicked(picked);
    } on PlatformException catch (error) {
      // Report what actually went wrong rather than guessing at permissions.
      // An earlier version blamed app permissions for every failure, which
      // sent debugging in the wrong direction for a whole test cycle - the
      // real cause was a CAMERA permission declared in the manifest but never
      // requested at runtime.
      if (kDebugMode) {
        debugPrint('IdDocumentPicker: [${error.code}] ${error.message}');
      }
      if (!context.mounted) return;
      _report(context, _describePlatformError(error));
    } catch (error) {
      // Anything that is not a PlatformException: MissingPluginException when
      // the app was hot-restarted after the plugin was added, UnimplementedError
      // on a desktop target that has no camera support, and so on.
      if (kDebugMode) {
        debugPrint('IdDocumentPicker: ${error.runtimeType} - $error');
      }
      if (!context.mounted) return;

      // In a debug build the real message is shown, because a generic
      // "please try again" has already cost two rounds of guessing at what
      // was actually wrong. Release builds keep the friendly wording.
      _report(
        context,
        kDebugMode
            ? '${error.runtimeType}: $error'
            : 'Could not open the picker. Please try again.',
      );
    }
  }

  /// Only mobile has a usable camera through image_picker. The desktop
  /// implementations are file-dialog only, and offering a camera button there
  /// produces an unimplemented error rather than a picker.
  bool get _cameraSupported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Maps the platform error codes image_picker actually emits.
  String _describePlatformError(PlatformException error) {
    switch (error.code) {
      case 'camera_access_denied':
        return 'Camera access was declined. Allow it when prompted, or pick '
            'from your gallery instead.';
      case 'photo_access_denied':
        return 'Photo access was declined. Allow it when prompted, or take a '
            'photo instead.';
      case 'invalid_image':
        return 'That file is not a readable image. Try another.';
      case 'multiple_request':
        return 'A picker is already open. Close it and try again.';
      case 'no_available_camera':
        return 'This device has no camera available. Pick from your gallery '
            'instead.';
      default:
        return error.message ?? 'Could not open the picker. Please try again.';
    }
  }

  void _report(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 8),
        content: Text(message),
      ),
    );
  }

  Future<void> _showSourceSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: AppSizes.sm),
            const Text(
              'Add your ID',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSizes.sm),
            if (_cameraSupported)
              ListTile(
                leading: const Icon(
                  Icons.photo_camera_rounded,
                  color: AppColors.primary,
                ),
                title: const Text('Take a photo'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pick(context, ImageSource.camera);
                },
              ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_rounded,
                color: AppColors.primary,
              ),
              title: Text(
                _cameraSupported ? 'Choose from gallery' : 'Choose a file',
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pick(context, ImageSource.gallery);
              },
            ),
            const SizedBox(height: AppSizes.sm),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      // Locked while uploading so a stray tap cannot swap the file mid-flight.
      onTap: isUploading ? null : () => _showSourceSheet(context),
      borderRadius: BorderRadius.circular(AppSizes.tileRadius),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: height,
        decoration: BoxDecoration(
          color: AppColors.primarySofter,
          borderRadius: BorderRadius.circular(AppSizes.tileRadius),
          border: Border.all(
            color: hasError
                ? AppColors.error
                : file != null
                ? AppColors.primary
                : AppColors.primarySoft,
            width: hasError || file != null ? 1.6 : 1.4,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (file == null)
              _EmptyState(title: emptyTitle, subtitle: emptySubtitle)
            else
              _BytesPreview(file: file!),

            if (file != null && !isUploading)
              Positioned(
                right: AppSizes.sm,
                bottom: AppSizes.sm,
                child: _Chip(icon: Icons.edit_rounded, label: 'Tap to change'),
              ),

            if (file != null && !isUploading && !hasError)
              const Positioned(
                left: AppSizes.sm,
                top: AppSizes.sm,
                child: _Chip(
                  icon: Icons.check_circle_rounded,
                  label: 'Ready to submit',
                  tint: AppColors.success,
                ),
              ),

            // The loading overlay. AnimatedOpacity rather than a conditional
            // child so the dim fades in instead of snapping.
            IgnorePointer(
              ignoring: !isUploading,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                opacity: isUploading ? 1 : 0,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.55),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const SizedBox(
                        width: 34,
                        height: 34,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSizes.md),
                      Text(
                        uploadLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Keep the app open',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 54,
          height: 54,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.add_photo_alternate_outlined,
            size: 26,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSizes.md),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryDark,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, this.tint});

  final IconData icon;
  final String label;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: 5),
      decoration: BoxDecoration(
        color: tint ?? Colors.black54,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders a picked image from its bytes.
///
/// `Image.file` needs a `dart:io` File, which does not exist on Flutter Web -
/// constructing one there throws at runtime, which is precisely what made the
/// picker look broken. Reading bytes through [XFile] and handing them to
/// `Image.memory` is the one path that works on web, Android, iOS and desktop.
class _BytesPreview extends StatelessWidget {
  const _BytesPreview({required this.file});

  final XFile file;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (BuildContext context, AsyncSnapshot<Uint8List> snapshot) {
        if (snapshot.hasError) {
          return const _EmptyState(
            title: 'That image could not be displayed',
            subtitle: 'Tap to pick another',
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          );
        }
        return Image.memory(snapshot.data!, fit: BoxFit.cover);
      },
    );
  }
}
