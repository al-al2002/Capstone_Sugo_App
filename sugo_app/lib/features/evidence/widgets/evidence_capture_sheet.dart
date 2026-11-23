import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_sheet.dart';
import '../../rb_cars/services/rb_cars_service.dart';

/// Takes the photos for one step of the work record (2026-11-22).
///
/// Camera only, on purpose: the record is evidence of what the technician saw
/// on this job, and a gallery picture could be from any day. The time is set
/// by the server when the photos are saved, and the location is stamped from
/// the phone's GPS - the sheet says so before the technician saves, because
/// nothing can be changed afterwards.
class EvidenceCaptureSheet extends StatefulWidget {
  const EvidenceCaptureSheet({
    super.key,
    required this.onSave,
    this.pickPhoto,
  });

  /// Saves the photos and note. Throws [RbCarsFailure] with a message to show.
  final Future<void> Function(List<XFile> photos, String? note) onSave;

  /// Tests pass a fake; the app opens the camera.
  final Future<XFile?> Function()? pickPhoto;

  static const int maxPhotos = 4;

  /// Opens the sheet. True when the photos were saved.
  static Future<bool?> show(
    BuildContext context, {
    required String label,
    required String blurb,
    required Future<void> Function(List<XFile> photos, String? note) onSave,
    Future<XFile?> Function()? pickPhoto,
  }) {
    return showSugoBottomSheet<bool>(
      context: context,
      title: 'Add $label photos',
      subtitle: blurb,
      builder: (_) => EvidenceCaptureSheet(onSave: onSave, pickPhoto: pickPhoto),
    );
  }

  @override
  State<EvidenceCaptureSheet> createState() => _EvidenceCaptureSheetState();
}

class _EvidenceCaptureSheetState extends State<EvidenceCaptureSheet> {
  final List<XFile> _photos = <XFile>[];
  final TextEditingController _note = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<XFile?> _camera() => ImagePicker().pickImage(
    source: ImageSource.camera,
    // Sharp enough to read a serial number, small enough to upload on mobile
    // data and stay under the bucket's 5 MB limit.
    maxWidth: 1600,
    imageQuality: 70,
  );

  Future<void> _take() async {
    if (_saving || _photos.length >= EvidenceCaptureSheet.maxPhotos) return;
    try {
      final XFile? photo = await (widget.pickPhoto ?? _camera)();
      if (photo == null || !mounted) return;
      setState(() {
        _photos.add(photo);
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open the camera.');
    }
  }

  Future<void> _save() async {
    if (_saving || _photos.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(List<XFile>.of(_photos), _note.text);
      if (mounted) Navigator.of(context).pop(true);
    } on RbCarsFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save the photos. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool full = _photos.length >= EvidenceCaptureSheet.maxPhotos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: AppSizes.sm,
          runSpacing: AppSizes.sm,
          children: <Widget>[
            for (int i = 0; i < _photos.length; i++)
              _Thumb(
                key: ValueKey<XFile>(_photos[i]),
                file: _photos[i],
                onRemove: _saving
                    ? null
                    : () => setState(() => _photos.removeAt(i)),
              ),
            if (!full)
              _TakeTile(
                count: _photos.length,
                onTap: _saving ? null : _take,
              ),
          ],
        ),
        const SizedBox(height: AppSizes.lg),
        TextField(
          key: const ValueKey<String>('evidence-note'),
          controller: _note,
          enabled: !_saving,
          maxLength: 500,
          minLines: 1,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Note (optional)',
            hintText: 'e.g. Screen already cracked at the corner',
          ),
        ),
        const SizedBox(height: AppSizes.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.lock_clock_outlined,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: Text(
                'Saved with the time and your location. Photos on the work '
                'record cannot be changed or deleted, so the client and SUGO '
                'can rely on them.',
                style: AppTextStyles.caption.copyWith(fontSize: 12.5),
              ),
            ),
          ],
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: AppSizes.md),
          Text(
            _error!,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: AppSizes.lg),
        SizedBox(
          height: AppSizes.buttonHeight,
          child: FilledButton(
            key: const ValueKey<String>('evidence-save'),
            onPressed: _photos.isEmpty || _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _photos.isEmpty
                        ? 'Take at least one photo'
                        : 'Save ${_photos.length} photo${_photos.length == 1 ? '' : 's'} to the work record',
                  ),
          ),
        ),
      ],
    );
  }
}

/// A photo taken in this sheet, with a remove button until it is saved.
class _Thumb extends StatelessWidget {
  const _Thumb({super.key, required this.file, required this.onRemove});

  final XFile file;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSizes.radius),
              child: FutureBuilder<Uint8List>(
                future: file.readAsBytes(),
                builder: (BuildContext context, AsyncSnapshot<Uint8List> s) =>
                    s.hasData
                    ? Image.memory(
                        s.data!,
                        fit: BoxFit.cover,
                        // A format the preview cannot draw (HEIC on some
                        // phones) still uploads; it just shows an icon here.
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: AppColors.primarySofter,
                          child: Icon(Icons.image_outlined, color: AppColors.primary),
                        ),
                      )
                    : const ColoredBox(color: AppColors.primarySofter),
              ),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 2,
              right: 2,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onRemove,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Take photo", with how many more fit.
class _TakeTile extends StatelessWidget {
  const _TakeTile({required this.count, required this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Take a photo',
      excludeSemantics: true,
      child: Material(
        color: AppColors.primarySofter,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        child: InkWell(
          key: const ValueKey<String>('evidence-take'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSizes.radius),
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSizes.radius),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(Icons.photo_camera_rounded, color: AppColors.primary),
                const SizedBox(height: 4),
                Text(
                  count == 0 ? 'Take photo' : '${EvidenceCaptureSheet.maxPhotos - count} more',
                  style: AppTextStyles.micro.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
