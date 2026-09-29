import 'dart:ui' show PathMetric;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_colors.dart';

/// Optional photos of the broken device.
///
/// Capped at [maxPhotos] and compressed on pick, because these are uploaded
/// over mobile data before the job is posted. Upload failure is not fatal -
/// see `RbCarsService.uploadPhotos` - so this widget never blocks the flow.
class PhotoPickerRow extends StatelessWidget {
  const PhotoPickerRow({
    super.key,
    required this.photos,
    required this.onAdd,
    required this.onRemove,
    this.maxPhotos = 4,
    this.existingUrls = const <String>[],
    this.onRemoveExisting,
  });

  final List<XFile> photos;
  final ValueChanged<XFile> onAdd;
  final ValueChanged<XFile> onRemove;
  final int maxPhotos;

  /// Photos already uploaded - on "Edit post", the ones the job was saved
  /// with. Shown first, and they count towards [maxPhotos].
  final List<String> existingUrls;
  final ValueChanged<String>? onRemoveExisting;

  Future<void> _pick(BuildContext context, ImageSource source) async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? file = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (file != null) onAdd(file);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the camera or gallery.')),
      );
    }
  }

  Future<void> _showSourceSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pick(context, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pick(context, ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Every slot is drawn, filled or not, so the row states the cap without a
    // sentence. A single "+" tile that silently stopped appearing at the
    // fourth photo left clients unsure whether more were allowed.
    final int kept = existingUrls.length;

    return Row(
      children: List<Widget>.generate(maxPhotos, (int index) {
        final bool isLast = index == maxPhotos - 1;

        final Widget tile;
        if (index < kept) {
          final String url = existingUrls[index];
          tile = _Thumbnail(
            image: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const _BrokenImage(),
            ),
            onRemove: onRemoveExisting == null
                ? null
                : () => onRemoveExisting!(url),
          );
        } else if (index - kept < photos.length) {
          final XFile file = photos[index - kept];
          tile = _Thumbnail(
            image: _FileImage(file: file),
            onRemove: () => onRemove(file),
          );
        } else {
          tile = _AddTile(onTap: () => _showSourceSheet(context));
        }

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: isLast ? 0 : AppSizes.sm),
            child: AspectRatio(aspectRatio: 1, child: tile),
          ),
        );
      }),
    );
  }
}

/// A filled photo slot: the picture, and a remove button when removable.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.image, required this.onRemove});

  final Widget image;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSizes.md),
            child: image,
          ),
        ),
        if (onRemove != null) Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 13,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A picked photo that has not been uploaded yet.
class _FileImage extends StatelessWidget {
  const _FileImage({required this.file});

  final XFile file;

  @override
  Widget build(BuildContext context) {
    // Bytes rather than a file handle: `Image.file` needs `dart:io`, which
    // does not exist on Flutter Web. Same fix as the ID picker.
    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (BuildContext context, AsyncSnapshot<Uint8List> snap) {
        if (snap.hasError) return const _BrokenImage();
        if (!snap.hasData) {
          return const ColoredBox(
            color: AppColors.divider,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return Image.memory(snap.data!, fit: BoxFit.cover);
      },
    );
  }
}

class _BrokenImage extends StatelessWidget {
  const _BrokenImage();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.divider,
      child: Icon(Icons.broken_image_outlined, color: AppColors.hint),
    );
  }
}

/// An empty photo slot.
///
/// Dashed rather than solid, which is the convention for "nothing here yet, put
/// something here" - a solid coral box reads as a filled state, and four of
/// them read as four photos already attached.
class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Add photo',
      child: Material(
        color: AppColors.primarySofter,
        borderRadius: BorderRadius.circular(AppSizes.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSizes.md),
          child: CustomPaint(
            painter: _DashedBorderPainter(),
            child: const Center(
              child: Icon(
                Icons.add_rounded,
                size: 22,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dashed rounded rectangle. Flutter has no dashed `BorderSide`, and the
/// alternative - a package, or a stack of little painted ticks - is more code
/// than walking the path once.
class _DashedBorderPainter extends CustomPainter {
  static const double _dash = 4;
  static const double _gap = 3.5;

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0.7, 0.7, size.width - 1.4, size.height - 1.4),
          const Radius.circular(AppSizes.md),
        ),
      );

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = AppColors.primary;

    for (final PathMetric metric in path.computeMetrics()) {
      double start = 0;
      while (start < metric.length) {
        final double end = (start + _dash).clamp(0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(start, end), paint);
        start = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) => false;
}
