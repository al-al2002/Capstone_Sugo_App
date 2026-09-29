import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/sugo_image_viewer.dart';
import '../services/chat_service.dart';

/// One message in a thread: text, a photo, or a photo with a caption.
///
/// ## Why the photo is inside the bubble rather than replacing it
///
/// A caption belongs to its picture. Drawing them as two bubbles means the
/// text can be read without the image that gives it meaning ("this is the
/// crack" above nothing), and it doubles the vertical space a single message
/// takes. So a photo message is one bubble: the picture, then the caption if
/// there is one, then the time and ticks.
///
/// ## Photo-only bubbles lose their padding
///
/// A picture with no caption fills the bubble edge to edge - padding around an
/// image is wasted space that makes the photo smaller for no gain. The
/// timestamp then sits *on* the image, over a soft scrim so it stays legible
/// against a light photo.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.body,
    required this.mine,
    this.imagePath,
    this.imageBytes,
    this.timestamp,
    this.isRead = false,
    this.pending = false,
    this.uploading = false,
    this.failed = false,
    this.onRetry,
    this.lastInGroup = true,
    this.service,
  });

  final String body;
  final bool mine;

  /// A stored photo, resolved to a signed URL when the bubble is built.
  final String? imagePath;

  /// A photo that has been picked but not uploaded yet, drawn from memory so
  /// the bubble appears the instant Send is pressed.
  final Uint8List? imageBytes;

  /// Last of a run from the same person: gets the tail and the full gap.
  final bool lastInGroup;
  final DateTime? timestamp;
  final bool isRead;
  final bool pending;
  final bool uploading;
  final bool failed;
  final VoidCallback? onRetry;

  /// Resolves [imagePath] to a signed URL. Required whenever [imagePath] is
  /// set; tests that only render text bubbles can leave it null.
  final ChatService? service;

  bool get _hasImage => imagePath != null || imageBytes != null;
  bool get _photoOnly => _hasImage && body.trim().isEmpty;

  @override
  Widget build(BuildContext context) {
    final Color background = failed
        ? AppColors.errorSoft
        : mine
        ? AppColors.primary
        : AppColors.surface;

    final Color foreground = mine && !failed
        ? Colors.white
        : AppColors.textPrimary;

    // The sheet corner: a bubble is its own kind of object, rounder than a
    // card, and the scale's larger corner says so without a third size.
    const Radius round = Radius.circular(AppSizes.sheetRadius);
    final BorderRadius corners = BorderRadius.only(
      topLeft: round,
      topRight: round,
      // The tail - a squared corner towards the speaker - only on the last
      // bubble of a turn.
      bottomLeft: !mine && lastInGroup
          ? const Radius.circular(AppSizes.xs)
          : round,
      bottomRight: mine && lastInGroup
          ? const Radius.circular(AppSizes.xs)
          : round,
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.76,
        ),
        child: Opacity(
          // A pending bubble is dimmed so "sending" is visible without a
          // spinner competing with the text.
          opacity: pending && !uploading ? 0.6 : 1,
          child: Container(
            margin: EdgeInsets.only(bottom: lastInGroup ? AppSizes.md : 3),
            decoration: BoxDecoration(
              color: background,
              borderRadius: corners,
              // Their bubbles are white with the hairline edge every card
              // has; no shadow since the Dispatch redesign.
              border: mine && !failed
                  ? null
                  : Border.all(
                      color: failed ? AppColors.error : AppColors.border,
                    ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (_hasImage)
                  _Photo(
                    path: imagePath,
                    bytes: imageBytes,
                    uploading: uploading,
                    service: service,
                    // The meta row is drawn over the photo when there is no
                    // caption to sit under.
                    overlay: _photoOnly ? _meta(foreground, onDark: true) : null,
                  ),
                if (!_photoOnly)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSizes.md + 2,
                      _hasImage ? AppSizes.sm : AppSizes.sm + 2,
                      AppSizes.md + 2,
                      AppSizes.sm + 2,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (body.trim().isNotEmpty)
                          Text(
                            body,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.4,
                              color: foreground,
                            ),
                          ),
                        const SizedBox(height: 3),
                        _meta(foreground),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Time, delivery state, and the retry affordance when a send failed.
  Widget _meta(Color foreground, {bool onDark = false}) {
    final Color muted = onDark
        ? Colors.white
        : mine
        ? Colors.white.withValues(alpha: 0.78)
        : AppColors.textSecondary;

    if (failed) {
      return GestureDetector(
        onTap: onRetry,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.error_outline_rounded,
              size: 13,
              color: AppColors.error,
            ),
            const SizedBox(width: 4),
            Text(
              'Not sent — tap to retry',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: onDark
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
          : EdgeInsets.zero,
      margin: onDark ? const EdgeInsets.all(AppSizes.sm) : EdgeInsets.zero,
      decoration: onDark
          ? BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(AppSizes.pillRadius),
            )
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            uploading
                ? 'Uploading…'
                : pending
                ? 'Sending…'
                : Fmt.time(timestamp ?? DateTime.now()),
            style: TextStyle(fontSize: 12, color: muted),
          ),
          if (mine && !pending) ...<Widget>[
            const SizedBox(width: 3),
            // Read turns the ticks bright, so "seen" is visible at a glance
            // rather than only by counting ticks.
            Icon(
              isRead ? Icons.done_all_rounded : Icons.done_rounded,
              size: 14,
              color: isRead
                  ? (onDark ? Colors.white : const Color(0xFFBFE3FF))
                  : muted,
            ),
          ],
        ],
      ),
    );
  }
}

/// The picture inside a bubble: from memory while it uploads, from a signed
/// URL once it is stored.
class _Photo extends StatelessWidget {
  const _Photo({
    required this.path,
    required this.bytes,
    required this.uploading,
    required this.service,
    this.overlay,
  });

  final String? path;
  final Uint8List? bytes;
  final bool uploading;
  final ChatService? service;
  final Widget? overlay;

  static const double _maxHeight = 260;

  @override
  Widget build(BuildContext context) {
    final Uint8List? local = bytes;

    final Widget image = local != null
        ? Image.memory(
            local,
            fit: BoxFit.cover,
            width: double.infinity,
          )
        : _RemotePhoto(path: path!, service: service);

    return Stack(
      alignment: Alignment.bottomRight,
      children: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: _maxHeight),
          child: GestureDetector(
            onTap: local != null || path == null
                ? null
                : () async {
                    final String? url = await service?.photoUrl(path!);
                    if (url != null && context.mounted) {
                      await openSugoImageViewer(context, urls: <String>[url]);
                    }
                  },
            child: image,
          ),
        ),
        if (uploading)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.35),
              child: const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
          ),
        if (overlay != null) overlay!,
      ],
    );
  }
}

class _RemotePhoto extends StatefulWidget {
  const _RemotePhoto({required this.path, required this.service});

  final String path;
  final ChatService? service;

  @override
  State<_RemotePhoto> createState() => _RemotePhotoState();
}

class _RemotePhotoState extends State<_RemotePhoto> {
  late Future<String> _url = _resolve();

  Future<String> _resolve() async {
    final ChatService? service = widget.service;
    if (service == null) throw StateError('No chat service for a photo bubble');
    return service.photoUrl(widget.path);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _url,
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
        if (snapshot.hasError) {
          return _Unavailable(
            onRetry: () => setState(() => _url = _resolve()),
          );
        }
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 180,
            width: 220,
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          );
        }
        return AnimatedSwitcher(
          duration: AppMotion.base,
          child: Image.network(
            snapshot.data!,
            key: ValueKey<String>(snapshot.data!),
            fit: BoxFit.cover,
            width: double.infinity,
            errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                _Unavailable(onRetry: () => setState(() => _url = _resolve())),
          ),
        );
      },
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 150,
      color: AppColors.divider,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(
            Icons.image_not_supported_outlined,
            size: 22,
            color: AppColors.hint,
          ),
          const SizedBox(height: AppSizes.xs),
          const Text(
            'Photo unavailable',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
