import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../../../core/widgets/sugo_avatar.dart';
import '../../../core/widgets/sugo_empty_state.dart';
import '../../../core/widgets/sugo_motion.dart';
import '../../../core/widgets/sugo_sheet.dart';
import '../../../core/widgets/sugo_skeleton.dart';
import '../../rb_cars/models/job_enums.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../models/chat_models.dart';
import '../services/chat_service.dart';
import '../widgets/chat_bubble.dart';

/// One conversation, scoped to a job.
///
/// ## Optimistic sending
///
/// A typed message appears immediately as a greyed bubble and is replaced when
/// the insert returns. Without it there is a visible pause between pressing
/// send and the bubble appearing, which on a slow connection reads as the app
/// having dropped the message - so people send it twice.
///
/// A failed send is kept and marked, with a retry, rather than silently
/// vanishing. Losing what someone typed is the worst thing a chat can do.
///
/// ## Photos
///
/// A picked photo is attached to the composer first, where it can be removed
/// or captioned, and only then sent - the brief's "preview, remove, send".
/// While it uploads, the bubble is already in the thread with a progress veil
/// over it, so the wait happens where the message will live rather than in a
/// modal. A failed upload keeps the picture and offers a retry.
class ChatThreadScreen extends StatefulWidget {
  const ChatThreadScreen({
    super.key,
    required this.jobId,
    required this.title,
    this.subtitle,
    this.avatarUrl,
    @visibleForTesting this.service,
  });

  final String jobId;

  /// The other person's name.
  final String title;

  /// The other person's photo, when the opener has it. Initials otherwise.
  final String? avatarUrl;

  /// Tests only. The app always uses the real service.
  final ChatService? service;

  /// What the job is, so a thread is identifiable when someone has two.
  final String? subtitle;

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  late final ChatService _service = widget.service ?? ChatService();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final ImagePicker _picker = ImagePicker();

  StreamSubscription<List<ChatMessage>>? _subscription;

  List<ChatMessage> _messages = const <ChatMessage>[];
  final List<PendingMessage> _pending = <PendingMessage>[];

  /// The photo waiting in the composer, before it is sent.
  XFile? _attachment;
  Uint8List? _attachmentBytes;

  bool _isLoading = true;
  String? _error;

  /// Where the unread divider goes: the id of the first message the other
  /// person sent that had not been read when this screen opened.
  ///
  /// Captured once, from the first delivery of the stream, and then left
  /// alone. Recomputing it would make the divider jump to the bottom the
  /// moment `markRead` lands, which defeats the point of it.
  String? _firstUnreadId;
  bool _unreadResolved = false;

  /// Every message id already on screen, and the ones that just arrived
  /// from the other person while the thread was open (2026-11-17). Only
  /// those animate in - the history that was there on opening does not, and
  /// neither do my own messages, which already animated in as pending
  /// bubbles and must not arrive twice.
  final Set<String> _seenIds = <String>{};
  final Set<String> _arriving = <String>{};

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _listen() {
    _subscription = _service
        .watch(widget.jobId)
        .listen(
          (List<ChatMessage> messages) {
            if (!mounted) return;
            final String? me = _service.currentUserId;
            setState(() {
              if (!_unreadResolved) {
                _unreadResolved = true;
                _firstUnreadId = messages
                    .where((ChatMessage m) => !m.isMine(me) && !m.isRead)
                    .firstOrNull
                    ?.id;
              } else {
                _arriving.addAll(
                  messages
                      .where(
                        (ChatMessage m) =>
                            !m.isMine(me) && !_seenIds.contains(m.id),
                      )
                      .map((ChatMessage m) => m.id),
                );
              }
              _seenIds.addAll(messages.map((ChatMessage m) => m.id));
              _messages = messages;
              _isLoading = false;
              _error = null;
            });
            // Anything the other side sent is read the moment it is on screen.
            unawaited(_service.markRead(widget.jobId));
            _scrollToEnd();
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _error = error is RbCarsFailure
                  ? error.message
                  : 'Could not load this conversation.';
            });
          },
        );
  }

  void _scrollToEnd() {
    // After the frame, so the list has its new extent.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: AppMotion.base,
        curve: AppMotion.standard,
      );
    });
  }

  // -------------------------------------------------------------- sending

  Future<void> _send() async {
    final String body = _input.text.trim();
    final XFile? photo = _attachment;

    if (body.isEmpty && photo == null) return;

    final PendingMessage draft = PendingMessage(
      localId: DateTime.now().microsecondsSinceEpoch.toString(),
      body: body,
      imageBytes: _attachmentBytes,
      uploading: photo != null,
    );

    setState(() {
      _pending.add(draft);
      _input.clear();
      _attachment = null;
      _attachmentBytes = null;
    });
    _scrollToEnd();

    try {
      if (photo == null) {
        await _service.send(widget.jobId, body);
      } else {
        await _service.sendPhoto(widget.jobId, photo, caption: body);
      }
      if (!mounted) return;
      // The stream will deliver the real row; drop the placeholder so the
      // message does not appear twice for a frame.
      setState(
        () => _pending.removeWhere(
          (PendingMessage p) => p.localId == draft.localId,
        ),
      );
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        final int index = _pending.indexWhere(
          (PendingMessage p) => p.localId == draft.localId,
        );
        if (index >= 0) {
          _pending[index] = _pending[index].copyWith(
            failed: true,
            uploading: false,
          );
        }
        // The picked file is kept so "retry" can send the same photo again.
        if (photo != null) {
          _retryable[draft.localId] = photo;
        }
      });
      UiFeedback.showError(context, failure.message);
    }
  }

  /// Photos whose send failed, kept so a retry does not ask for the file
  /// again. Cleared when the retry succeeds or the message is dropped.
  final Map<String, XFile> _retryable = <String, XFile>{};

  Future<void> _retry(PendingMessage message) async {
    final XFile? photo = _retryable.remove(message.localId);

    setState(() {
      _pending.removeWhere((PendingMessage p) => p.localId == message.localId);
      if (photo == null) {
        // A text message goes back into the box, so it can be edited before
        // being sent again.
        _input.text = message.body;
        _input.selection = TextSelection.collapsed(offset: message.body.length);
      } else {
        _attachment = photo;
        _attachmentBytes = message.imageBytes;
        _input.text = message.body;
      }
    });

    if (photo != null) await _send();
  }

  // --------------------------------------------------------------- photos

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        // Downscaled hard on purpose: a chat photo is looked at on a phone,
        // it travels over mobile data, and the bucket caps at 5 MB.
        maxWidth: 1600,
        imageQuality: 78,
      );
      // Null simply means the person backed out of the camera or picker.
      if (picked == null) return;

      final Uint8List bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _attachment = picked;
        _attachmentBytes = bytes;
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

  Future<void> _openAttachSheet() async {
    // Only mobile has a usable camera through image_picker; the desktop
    // implementations are file-dialog only, so offering a camera button there
    // would raise an unimplemented error rather than open anything.
    final bool hasCamera =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;

    await showSugoBottomSheet<void>(
      context: context,
      title: 'Send a photo',
      subtitle:
          'Photos help your technician understand the problem before they '
          'arrive.',
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
            label: hasCamera ? 'Choose from gallery' : 'Choose a file',
            hint: 'Pick an existing picture',
            onTap: () {
              Navigator.of(sheetContext).pop();
              _pickPhoto(ImageSource.gallery);
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: SugoAppBar(
        surface: true,
        showDivider: true,
        centerTitle: false,
        titleWidget: Row(
          children: <Widget>[
            SugoAvatar(
              name: widget.title,
              imageUrl: widget.avatarUrl,
              size: AppSizes.avatarSm,
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.titleSmall.copyWith(fontSize: 15),
                  ),
                  if (widget.subtitle != null)
                    Text(
                      widget.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.micro,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: CustomPaint(painter: const _DotBackdrop(), child: _body()),
            ),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_isLoading) {
      return ListView(
        padding: const EdgeInsets.all(AppSizes.lg),
        children: const <Widget>[SugoSkeletonList(count: 4, showAvatar: false)],
      );
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        children: <Widget>[
          SugoEmptyState.error(
            title: 'This conversation did not load',
            message: '$_error Check your connection and try again.',
            onAction: () {
              setState(() {
                _isLoading = true;
                _error = null;
              });
              _subscription?.cancel();
              _listen();
            },
          ),
        ],
      );
    }

    if (_messages.isEmpty && _pending.isEmpty) {
      return _EmptyThread(
        name: widget.title.split(' ').first,
        // A starter fills the box rather than sending, so it can be edited.
        onStarter: (String text) {
          _input.text = text;
          _input.selection = TextSelection.collapsed(offset: text.length);
        },
      );
    }

    final String? me = _service.currentUserId;
    final int total = _messages.length + _pending.length;

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
        AppSizes.md,
        AppSizes.sm,
        AppSizes.md,
        AppSizes.lg,
      ),
      itemCount: total,
      itemBuilder: (BuildContext context, int index) {
        if (index < _messages.length) {
          final ChatMessage message = _messages[index];
          final bool mine = message.isMine(me);

          // A date divider whenever the day changes, so a thread spanning
          // several days is readable.
          final bool showDay =
              index == 0 ||
              !_sameDay(_messages[index - 1].createdAt, message.createdAt);

          // Consecutive messages from one person within a few minutes read
          // as one turn: tighter spacing, and the bubble's tail only on the
          // last of them - the way a conversation is actually paced.
          final ChatMessage? next = index + 1 < _messages.length
              ? _messages[index + 1]
              : null;
          final bool lastInGroup =
              next == null ||
              next.isMine(me) != mine ||
              next.createdAt.difference(message.createdAt) > _groupGap ||
              !_sameDay(next.createdAt, message.createdAt);

          return Column(
            crossAxisAlignment: mine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: <Widget>[
              if (showDay) _DayDivider(date: message.createdAt),
              if (message.id == _firstUnreadId) const _UnreadDivider(),
              _ArrivingBubble(
                key: ValueKey<String>(message.id),
                mine: mine,
                animate: _arriving.contains(message.id),
                child: ChatBubble(
                  body: message.body,
                  mine: mine,
                  imagePath: message.imagePath,
                  service: _service,
                  timestamp: message.createdAt,
                  isRead: message.isRead,
                  lastInGroup: lastInGroup,
                ),
              ),
            ],
          );
        }

        final PendingMessage pending = _pending[index - _messages.length];
        // A message I just sent always arrives - this is its one entrance.
        return _ArrivingBubble(
          key: ValueKey<String>('pending-${pending.localId}'),
          mine: true,
          animate: true,
          child: ChatBubble(
            body: pending.body,
            mine: true,
            imageBytes: pending.imageBytes,
            pending: !pending.failed,
            uploading: pending.uploading,
            failed: pending.failed,
            onRetry: pending.failed ? () => _retry(pending) : null,
          ),
        );
      },
    );
  }

  /// How close two messages must be to count as one turn.
  static const Duration _groupGap = Duration(minutes: 5);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _composer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.sm,
        AppSizes.sm,
        AppSizes.sm,
        AppSizes.sm,
      ),
      // A floating tray: rounded on top and lifted by a soft shadow, so the
      // composer reads as the thing you hold rather than the page's footer.
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppSizes.sheetRadius),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // The attached photo, before it is sent: previewed, removable.
          AnimatedSize(
            duration: AppMotion.base,
            curve: AppMotion.standard,
            alignment: Alignment.topCenter,
            child: _attachmentBytes == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(
                      left: AppSizes.xs,
                      right: AppSizes.xs,
                      bottom: AppSizes.sm,
                    ),
                    child: Row(
                      children: <Widget>[
                        Stack(
                          clipBehavior: Clip.none,
                          children: <Widget>[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(
                                AppSizes.tileRadius,
                              ),
                              child: Image.memory(
                                _attachmentBytes!,
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: -6,
                              right: -6,
                              child: Material(
                                color: AppColors.navy,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () => setState(() {
                                    _attachment = null;
                                    _attachmentBytes = null;
                                  }),
                                  child: const Padding(
                                    padding: EdgeInsets.all(3),
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 15,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: AppSizes.md),
                        Expanded(
                          child: Text(
                            'Photo ready to send. Add a note if it helps.',
                            style: AppTextStyles.micro,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Container(
                width: AppSizes.touchTarget,
                height: AppSizes.touchTarget,
                decoration: const BoxDecoration(
                  color: AppColors.primarySofter,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  tooltip: 'Attach a photo',
                  onPressed: _openAttachSheet,
                  icon: const Icon(Icons.add_photo_alternate_rounded, size: 22),
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _send(),
                  style: const TextStyle(fontSize: 15, height: 1.35),
                  decoration: InputDecoration(
                    hintText: _attachmentBytes == null
                        ? 'Write a message…'
                        : 'Add a caption…',
                    counterText: '',
                    filled: true,
                    fillColor: AppColors.background,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.lg,
                      vertical: 12,
                    ),
                    // A pill, not the form-field box: this is a conversation,
                    // not a form, and the shape says so before anyone types.
                    border: _pill(AppColors.border),
                    enabledBorder: _pill(AppColors.border),
                    focusedBorder: _pill(AppColors.secondary, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              // Rebuilds on every keystroke so the button is live only when
              // there is something to send - and grows in when it becomes live.
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _input,
                builder: (BuildContext context, TextEditingValue value, _) {
                  final bool canSend =
                      value.text.trim().isNotEmpty || _attachmentBytes != null;
                  // Grows in and leans forward when there is something to
                  // send, in the brand gradient (2026-11-17); grey and level
                  // when there is not. 48 across, the touch floor.
                  return AnimatedScale(
                    scale: canSend ? 1 : 0.88,
                    duration: AppMotion.fast,
                    curve: AppMotion.standard,
                    child: AnimatedRotation(
                      turns: canSend ? -0.06 : 0,
                      duration: AppMotion.base,
                      curve: AppMotion.emphasized,
                      child: AnimatedContainer(
                        duration: AppMotion.base,
                        width: AppSizes.touchTarget,
                        height: AppSizes.touchTarget,
                        decoration: BoxDecoration(
                          gradient: canSend
                              ? const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: <Color>[
                                    AppColors.primary,
                                    AppColors.secondary,
                                  ],
                                )
                              : null,
                          color: canSend ? null : AppColors.border,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          tooltip: 'Send',
                          onPressed: canSend ? _send : null,
                          icon: const Icon(
                            Icons.send_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  static OutlineInputBorder _pill(Color color, {double width = 1.2}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSizes.md),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSizes.pillRadius),
          border: Border.all(color: AppColors.divider),
        ),
        child: Text(
          Fmt.dayHeading(date),
          style: AppTextStyles.micro.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// "New messages", drawn where reading last stopped.
class _UnreadDivider extends StatelessWidget {
  const _UnreadDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
      child: Row(
        children: <Widget>[
          const Expanded(child: Divider(color: AppColors.accentSoft)),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(AppSizes.pillRadius),
            ),
            child: Text(
              'New messages',
              style: AppTextStyles.overline.copyWith(
                color: AppColors.accentDark,
              ),
            ),
          ),
          const Expanded(child: Divider(color: AppColors.accentSoft)),
        ],
      ),
    );
  }
}

/// A bubble arriving: it grows from its speaker's side of the thread - the
/// corner its tail points at - and fades in, once (2026-11-17).
class _ArrivingBubble extends StatefulWidget {
  const _ArrivingBubble({
    super.key,
    required this.mine,
    required this.animate,
    required this.child,
  });

  final bool mine;
  final bool animate;
  final Widget child;

  @override
  State<_ArrivingBubble> createState() => _ArrivingBubbleState();
}

class _ArrivingBubbleState extends State<_ArrivingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppMotion.slow,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: AppMotion.emphasized,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.animate && !AppMotion.reduced(context)) {
      _c.forward();
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Alignment corner = widget.mine
        ? Alignment.bottomRight
        : Alignment.bottomLeft;
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (BuildContext context, Widget? child) => Opacity(
        opacity: _t.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset((1 - _t.value) * (widget.mine ? 18 : -18), 0),
          child: Transform.scale(
            scale: 0.86 + 0.14 * _t.value,
            alignment: corner,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The faint dot grid behind a conversation: a texture, so the thread reads
/// as its own space rather than a plain page, without competing with text.
class _DotBackdrop extends CustomPainter {
  const _DotBackdrop();

  static const double _gap = 22;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint dot = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.055);
    for (double y = _gap / 2; y < size.height; y += _gap) {
      final double shift = ((y / _gap).floor().isOdd) ? _gap / 2 : 0;
      for (double x = _gap / 2 + shift; x < size.width; x += _gap) {
        canvas.drawCircle(Offset(x, y), 1.3, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_DotBackdrop oldDelegate) => false;
}

/// Opens a thread for a job, from anywhere.
Future<void> openChatThread(
  BuildContext context, {
  required String jobId,
  required String title,
  String? subtitle,
  String? avatarUrl,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChatThreadScreen(
        jobId: jobId,
        title: title,
        subtitle: subtitle,
        avatarUrl: avatarUrl,
      ),
    ),
  );
}

/// Human label for a job, used as a thread subtitle, e.g. `Laptop / PC ·
/// Confirmed`. Takes the device wire value and prints its label - it used to
/// print the raw wire, so threads read "laptop · Confirmed".
String jobThreadSubtitle(String deviceType, String symptom, JobStatus status) {
  final String device = deviceType.isEmpty
      ? 'Job'
      : DeviceType.fromWire(deviceType)?.label ?? deviceType;
  return '$device · ${status.label}';
}

/// A thread with nothing in it yet: who it is with, and a few ways to start.
///
/// The starters fill the box instead of sending, so the first message can
/// still be made the client's or technician's own words.
class _EmptyThread extends StatelessWidget {
  const _EmptyThread({required this.name, required this.onStarter});

  final String name;
  final ValueChanged<String> onStarter;

  static const List<String> _starters = <String>[
    'Hello! Thanks for taking this job.',
    'What time works for you?',
    'Can you send me an update?',
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSizes.xl),
      children: <Widget>[
        const SizedBox(height: AppSizes.xl),
        // The hand waves three times and settles (2026-11-17), on a soft
        // gradient disc - a greeting, not a loading spinner.
        SugoRiseIn(
          child: Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[AppColors.primarySoft, AppColors.cyanSoft],
                ),
              ),
              child: const SugoWiggle(
                alignment: Alignment(0.3, 0.8), // the wrist
                angle: 0.38,
                child: Icon(
                  Icons.waving_hand_rounded,
                  size: 38,
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSizes.lg),
        SugoRiseIn(
          delay: AppMotion.staggerDelay(1),
          child: Column(
            children: <Widget>[
              Text(
                'Say hello to $name',
                textAlign: TextAlign.center,
                style: AppTextStyles.title,
              ),
              const SizedBox(height: AppSizes.xs),
              Text(
                'Agree a time, confirm the address, or send a photo of the '
                'problem.',
                textAlign: TextAlign.center,
                style: AppTextStyles.subtitle,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.xl),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSizes.sm,
          runSpacing: AppSizes.sm,
          children: <Widget>[
            for (int i = 0; i < _starters.length; i++)
              SugoRiseIn(
                delay: AppMotion.staggerDelay(i + 2),
                child: ActionChip(
                  avatar: const Icon(
                    Icons.auto_awesome_rounded,
                    size: 15,
                    color: AppColors.secondary,
                  ),
                  label: Text(_starters[i]),
                  onPressed: () => onStarter(_starters[i]),
                  backgroundColor: AppColors.surface,
                  side: const BorderSide(color: AppColors.primarySoft),
                  labelStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
