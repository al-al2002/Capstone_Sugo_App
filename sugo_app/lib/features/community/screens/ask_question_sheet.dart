import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/sugo_dialog.dart';
import '../../../core/widgets/sugo_icon_button.dart';
import '../../../core/widgets/sugo_sheet.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../models/community_models.dart';
import '../services/community_service.dart';

/// The "ask the community" composer.
///
/// ## Why a sheet and not a screen
///
/// Asking a question is a short, interruptible act taken from the middle of
/// browsing. A full route pushes the feed off-screen and makes the return
/// journey a navigation event; a sheet keeps the feed visible behind it, which
/// is what makes abandoning the draft feel cheap. Anything the user might
/// reasonably not finish belongs in a sheet.
///
/// ## Why the title and the detail are separate fields
///
/// One free-text box produces questions like "help pls my laptop". Two fields
/// ask two different things - what is the question, and what is the context -
/// and the technician answering needs both. The character counter on the title
/// is there because the database rejects anything under 8 characters, and a
/// silent rejection after tapping Post is the worst possible way to learn that.
class AskQuestionSheet extends StatefulWidget {
  const AskQuestionSheet({super.key});

  /// Opens the composer. Resolves to the stored post, or null if dismissed.
  static Future<CommunityPost?> show(BuildContext context) {
    return showModalBottomSheet<CommunityPost>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // The feed stays legible behind the sheet, which is the point of using
      // one - a solid scrim would make this indistinguishable from a route.
      barrierColor: AppColors.navy.withValues(alpha: 0.32),
      builder: (_) => const AskQuestionSheet(),
    );
  }

  @override
  State<AskQuestionSheet> createState() => _AskQuestionSheetState();
}

class _AskQuestionSheetState extends State<AskQuestionSheet> {
  final CommunityService _service = CommunityService();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  final FocusNode _titleFocus = FocusNode();
  final ImagePicker _picker = ImagePicker();

  CommunityTopic _topic = CommunityTopic.general;
  bool _posting = false;

  /// The chosen photo, and its bytes for the preview.
  ///
  /// The bytes are held separately because `Image.file` does not work on the
  /// web and a second `readAsBytes` per rebuild would re-read the file on
  /// every keystroke.
  XFile? _photo;
  Uint8List? _photoBytes;

  static const int _titleMin = 8;
  static const int _titleMax = 160;
  static const int _bodyMin = 10;

  @override
  void initState() {
    super.initState();
    _title.addListener(_onChanged);
    _body.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  bool get _canPost =>
      _title.text.trim().length >= _titleMin &&
      _body.text.trim().length >= _bodyMin &&
      !_posting;

  /// What is still missing, phrased as the next action.
  ///
  /// A disabled button with no explanation is the single most common way a
  /// user concludes a form is broken.
  String? get _blockedReason {
    if (_posting) return null;
    final int titleLength = _title.text.trim().length;
    final int bodyLength = _body.text.trim().length;

    if (titleLength == 0 && bodyLength == 0) return null;
    if (titleLength < _titleMin) {
      return 'Your question needs at least $_titleMin characters.';
    }
    if (bodyLength < _bodyMin) {
      return 'Add a little detail so a technician can answer properly.';
    }
    return null;
  }

  // --------------------------------------------------------------- photos

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        // Same ceiling as a chat photo: it is looked at on a phone, it travels
        // over mobile data, and the bucket caps at 5 MB.
        maxWidth: 1600,
        imageQuality: 78,
      );
      // Null simply means the person backed out of the camera or picker.
      if (picked == null) return;

      final Uint8List bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photo = picked;
        _photoBytes = bytes;
      });
    } catch (error) {
      if (!mounted) return;
      UiFeedback.showError(
        context,
        kDebugMode
            ? 'Could not open the picker: $error'
            : 'Could not open the picker. Please try again.',
      );
    }
  }

  Future<void> _openPhotoSheet() async {
    // Only mobile has a usable camera through image_picker; the desktop
    // implementations are file-dialog only, so a camera button there would
    // raise an unimplemented error rather than open anything.
    final bool hasCamera =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;

    await showSugoBottomSheet<void>(
      context: context,
      title: 'Add a photo',
      subtitle:
          'A picture of the problem - a screen, a port, an error message - '
          'gets you a far more specific answer.',
      builder: (BuildContext sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (hasCamera)
            SugoSheetOption(
              icon: Icons.photo_camera_rounded,
              label: 'Take a photo',
              hint: 'Use the camera now',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickPhoto(ImageSource.camera);
              },
            ),
          SugoSheetOption(
            icon: Icons.photo_library_rounded,
            label: 'Choose from gallery',
            hint: 'Pick one you already have',
            onTap: () {
              Navigator.of(sheetContext).pop();
              _pickPhoto(ImageSource.gallery);
            },
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- leaving

  /// True when there is something a user would be upset to lose.
  bool get _hasDraft =>
      _title.text.trim().isNotEmpty ||
      _body.text.trim().isNotEmpty ||
      _photo != null;

  /// Closes the composer, confirming first if anything has been typed.
  ///
  /// A sheet is meant to be cheap to abandon, which is why this asks rather
  /// than blocks - but a half-written question lost to a mis-tap on the back
  /// arrow is the one case where "cheap to abandon" stops being a virtue.
  Future<void> _close() async {
    if (_posting) return;

    if (_hasDraft) {
      final bool discard = await showSugoConfirmDialog(
        context: context,
        title: 'Discard this question?',
        message: 'Your draft will not be saved.',
        confirmLabel: 'Discard',
        cancelLabel: 'Keep writing',
        destructive: true,
        icon: Icons.delete_outline_rounded,
      );
      if (!discard) return;
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _post() async {
    setState(() => _posting = true);

    try {
      final CommunityPost stored = await _service.ask(
        title: _title.text,
        body: _body.text,
        topic: _topic,
        photo: _photo,
      );
      if (!mounted) return;
      Navigator.of(context).pop(stored);
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      setState(() => _posting = false);
      UiFeedback.showError(context, failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Lifts the sheet above the keyboard, so the field being typed into is
    // never the one hidden by it.
    final double inset = MediaQuery.of(context).viewInsets.bottom;

    return PopScope(
      // The back gesture goes through the same guard as the back button, so
      // there is no route out of a draft that skips the confirmation.
      canPop: !_hasDraft && !_posting,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) _close();
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppSizes.sheetRadius),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(AppSizes.screenPadding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const _Grabber(),
                    const SizedBox(height: AppSizes.md),

                    // The back arrow: the composer covers the feed, and until
                    // now the only ways out were a drag on the grabber, which
                    // is not obvious, and a Cancel button below the fold once
                    // the keyboard was up. A back arrow is where everyone
                    // already looks for "take me out of here".
                    Row(
                      children: <Widget>[
                        SugoIconButton(
                          icon: Icons.arrow_back_rounded,
                          tooltip: 'Back to the community',
                          onPressed: _posting ? null : _close,
                        ),
                        const SizedBox(width: AppSizes.sm),
                        Expanded(
                          child: Text(
                            'Ask the community',
                            style: AppTextStyles.title,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSizes.sm),
                    Text(
                      'Verified technicians answer here. Rate the answers that '
                      'help — it is how they build their reputation.',
                      style: AppTextStyles.subtitle,
                    ),
                    const SizedBox(height: AppSizes.xl),

                    _Label(
                      text: 'Your question',
                      counter: '${_title.text.trim().length}/$_titleMax',
                      warn: _title.text.trim().length > _titleMax,
                    ),
                    const SizedBox(height: AppSizes.sm),
                    TextField(
                      controller: _title,
                      focusNode: _titleFocus,
                      autofocus: true,
                      maxLength: _titleMax,
                      textCapitalization: TextCapitalization.sentences,
                      style: AppTextStyles.bodyStrong,
                      decoration: const InputDecoration(
                        hintText:
                            'e.g. Best laptop specs for a student on a budget?',
                        // The field has its own counter in the label row,
                        // which sits where it can be read before the limit is
                        // hit.
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: AppSizes.lg),

                    const _Label(text: 'Details'),
                    const SizedBox(height: AppSizes.sm),
                    TextField(
                      controller: _body,
                      maxLines: 5,
                      maxLength: 4000,
                      textCapitalization: TextCapitalization.sentences,
                      style: AppTextStyles.body,
                      decoration: const InputDecoration(
                        hintText:
                            'What have you tried? What is your budget? The '
                            'more context you give, the better the answers.',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: AppSizes.lg),

                    const _Label(text: 'Photo', optional: true),
                    const SizedBox(height: AppSizes.sm),
                    _PhotoField(
                      bytes: _photoBytes,
                      enabled: !_posting,
                      onPick: _openPhotoSheet,
                      onRemove: () => setState(() {
                        _photo = null;
                        _photoBytes = null;
                      }),
                    ),
                    const SizedBox(height: AppSizes.lg),

                    const _Label(text: 'Topic'),
                    const SizedBox(height: AppSizes.sm),
                    _TopicPicker(
                      selected: _topic,
                      onChanged: (CommunityTopic topic) =>
                          setState(() => _topic = topic),
                    ),
                    const SizedBox(height: AppSizes.xl),

                    if (_blockedReason != null) ...<Widget>[
                      Row(
                        children: <Widget>[
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _blockedReason!,
                              style: AppTextStyles.caption,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSizes.sm),
                    ],

                    PrimaryButton(
                      label: 'Post question',
                      isLoading: _posting,
                      onPressed: _canPost ? _post : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The drag handle. Signals the sheet can be dismissed by dragging, which is
/// otherwise invisible.
class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({
    required this.text,
    this.counter,
    this.warn = false,
    this.optional = false,
  });

  final String text;
  final String? counter;
  final bool warn;

  /// Marks a field nobody has to fill in. Said in the label rather than left
  /// to be inferred: an unmarked field on a form is read as required, and a
  /// question that would have been asked does not get asked.
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(text, style: AppTextStyles.label),
        if (optional) ...<Widget>[
          const SizedBox(width: 6),
          Text(
            'Optional',
            style: AppTextStyles.micro,
          ),
        ],
        const Spacer(),
        if (counter != null)
          Text(
            counter!,
            style: AppTextStyles.micro.copyWith(
              color: warn ? AppColors.error : AppColors.hint,
              fontWeight: warn ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
      ],
    );
  }
}

/// The optional photo: an invitation when empty, a preview once chosen.
///
/// ## Why the empty state is a wide tile and not an icon button
///
/// A paperclip in a corner is discoverable to someone already looking for it.
/// Most people asking here are not - they are describing a fault in words
/// because they do not know a photo is allowed. A labelled tile the width of
/// the form says what it does before it is tapped, and costs one row of a
/// sheet that is already scrolling.
class _PhotoField extends StatelessWidget {
  const _PhotoField({
    required this.bytes,
    required this.enabled,
    required this.onPick,
    required this.onRemove,
  });

  final Uint8List? bytes;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final Uint8List? data = bytes;

    if (data == null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPick : null,
          borderRadius: BorderRadius.circular(AppSizes.cardRadius),
          child: Container(
            padding: const EdgeInsets.all(AppSizes.md),
            decoration: BoxDecoration(
              color: AppColors.fieldFill,
              borderRadius: BorderRadius.circular(AppSizes.cardRadius),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(AppSizes.sm + 2),
                  ),
                  child: const Icon(
                    Icons.add_a_photo_outlined,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text('Add a photo', style: AppTextStyles.bodyStrong),
                      const SizedBox(height: 2),
                      Text(
                        'Show the problem — you will get a better answer.',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      child: Stack(
        children: <Widget>[
          // A fixed aspect ratio rather than the photo's own: a portrait
          // phone shot would otherwise push the Post button two screens down.
          AspectRatio(
            aspectRatio: 16 / 10,
            child: Image.memory(data, fit: BoxFit.cover, width: double.infinity),
          ),
          Positioned(
            top: AppSizes.sm,
            right: AppSizes.sm,
            child: Material(
              color: AppColors.navy.withValues(alpha: 0.62),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: enabled ? onRemove : null,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: AppSizes.sm,
            bottom: AppSizes.sm,
            child: Material(
              color: AppColors.navy.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(AppSizes.pillRadius),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                onTap: enabled ? onPick : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.md,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(
                        Icons.swap_horiz_rounded,
                        size: 15,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Replace',
                        style: AppTextStyles.micro.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicPicker extends StatelessWidget {
  const _TopicPicker({required this.selected, required this.onChanged});

  final CommunityTopic selected;
  final ValueChanged<CommunityTopic> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSizes.sm,
      runSpacing: AppSizes.sm,
      children: CommunityTopic.values.map((CommunityTopic topic) {
        final bool active = topic == selected;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onChanged(topic),
            borderRadius: BorderRadius.circular(AppSizes.pillRadius),
            child: AnimatedContainer(
              duration: AppMotion.fast,
              curve: AppMotion.standard,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.md + 2,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: active ? AppColors.primarySoft : AppColors.fieldFill,
                borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                border: Border.all(
                  color: active ? AppColors.primary : AppColors.border,
                  width: active ? 1.4 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    topic.icon,
                    size: 14,
                    color: active
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    topic.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                      color: active
                          ? AppColors.primaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}
