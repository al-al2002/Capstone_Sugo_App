import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../models/chat_models.dart';

/// Reads and writes job chat.
///
/// ## Why every call is a plain table operation
///
/// Unlike matching or review, nothing here needs elevated privilege. RLS on
/// `job_messages` already answers the only question that matters - "is the
/// caller a party to this job?" - through `is_job_participant()`. An edge
/// function would add a hop and a second place for that rule to live.
///
/// Since `20260923000003_negotiation_chat.sql` a party means three people,
/// not two: the client, the assigned technician, and the technician the
/// client has *offered* the job to but who has not answered yet. That last
/// one is what lets a technician ask "your budget will not cover the part -
/// can you go to ₱2,400?" instead of declining without a word.
///
/// The one thing the client cannot do is edit or delete a message: there is no
/// delete policy, and the update guard pins the writable column to `read_at`.
class ChatService {
  ChatService({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  static const String _table = 'job_messages';

  /// Realtime can be absent - the publication is added conditionally in
  /// migration 20260907000013 - so the thread also polls. Six seconds is
  /// frequent enough to feel like chat if realtime is missing, and cheap
  /// enough not to matter when it is not.
  static const Duration pollInterval = Duration(seconds: 6);

  String? get currentUserId => _client.auth.currentUser?.id;

  String get _uid {
    final String? id = currentUserId;
    if (id == null) {
      throw const RbCarsFailure('Please sign in again to continue.');
    }
    return id;
  }

  // --------------------------------------------------------- conversations

  /// Every job the caller can chat about, newest activity first.
  Future<List<Conversation>> conversations() async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('job_conversations')
          .select()
          // Nulls last so a brand-new thread with no messages does not sort
          // above an active one.
          .order('last_message_at', ascending: false, nullsFirst: false);

      return rows.map(Conversation.fromJson).toList(growable: false);
    } on PostgrestException catch (error) {
      _log('conversations', error);
      throw const RbCarsFailure('Could not load your conversations.');
    }
  }

  /// Unread messages on one job, for a thread the conversation list does not
  /// carry.
  ///
  /// That is one case only: a technician negotiating a job they have not
  /// accepted. `job_conversations` reads `jobs` as the caller, and an
  /// unassigned job is not theirs to read - see
  /// `20260923000003_negotiation_chat.sql` for why widening that would hand
  /// over the client's row as well. So the badge on the offer card counts the
  /// messages directly, which RLS does allow them.
  ///
  /// Zero on failure, like every other badge here.
  Future<int> unreadForJob(String jobId) async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from(_table)
          .select('id')
          .eq('job_id', jobId)
          .neq('sender_id', _uid)
          .isFilter('read_at', null);

      return rows.length;
    } catch (error) {
      _log('unreadForJob', error);
      return 0;
    }
  }

  /// Total unread messages across every thread, for the tab badge.
  Future<int> unreadTotal() async {
    try {
      final List<Conversation> all = await conversations();
      return all.fold<int>(0, (int sum, Conversation c) => sum + c.unreadCount);
    } catch (error) {
      // A badge is decoration. Failing to load it must never surface as an
      // error over the dashboard.
      _log('unreadTotal', error);
      return 0;
    }
  }

  // ---------------------------------------------------------------- thread

  Future<List<ChatMessage>> messages(String jobId) async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from(_table)
          .select()
          .eq('job_id', jobId)
          .order('created_at');

      return rows.map(ChatMessage.fromJson).toList(growable: false);
    } on PostgrestException catch (error) {
      _log('messages', error);
      throw const RbCarsFailure('Could not load this conversation.');
    }
  }

  /// Live thread: emits what is stored, then again on every change.
  ///
  /// Mirrors `TrackingService.watch` deliberately - realtime subscription plus
  /// a polling safety net, so the screen stays truthful on a project where the
  /// `supabase_realtime` publication was never created.
  Stream<List<ChatMessage>> watch(String jobId) {
    final StreamController<List<ChatMessage>> controller =
        StreamController<List<ChatMessage>>.broadcast();

    RealtimeChannel? channel;
    Timer? poller;

    Future<void> emitCurrent() async {
      try {
        final List<ChatMessage> current = await messages(jobId);
        if (!controller.isClosed) controller.add(current);
      } catch (error) {
        if (!controller.isClosed) controller.addError(error);
      }
    }

    controller.onListen = () {
      unawaited(emitCurrent());

      channel = _client
          .channel('job_messages:$jobId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: _table,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'job_id',
              value: jobId,
            ),
            // Re-reads the thread rather than appending the payload row.
            // An update (a read receipt) and a delete would otherwise need
            // separate handling, and the thread is a few dozen rows.
            callback: (PostgresChangePayload _) => unawaited(emitCurrent()),
          )
          .subscribe();

      poller = Timer.periodic(pollInterval, (_) => emitCurrent());
    };

    controller.onCancel = () async {
      poller?.cancel();
      final RealtimeChannel? open = channel;
      if (open != null) await _client.removeChannel(open);
    };

    return controller.stream;
  }

  /// Sends a message and returns the stored row.
  ///
  /// `sender_id` is set from the session, never from the caller. The insert
  /// policy requires `sender_id = auth.uid()` anyway, so a forged value fails -
  /// but sending the right one means the failure never happens.
  Future<ChatMessage> send(String jobId, String body) async {
    final String trimmed = body.trim();

    if (trimmed.isEmpty) {
      throw const RbCarsFailure('Type a message first.');
    }
    if (trimmed.length > 2000) {
      throw const RbCarsFailure('That message is too long (2000 characters).');
    }

    try {
      final Map<String, dynamic> row = await _client
          .from(_table)
          .insert(<String, dynamic>{
            'job_id': jobId,
            'sender_id': _uid,
            'body': trimmed,
          })
          .select()
          .single();

      return ChatMessage.fromJson(row);
    } on PostgrestException catch (error) {
      _log('send', error);

      if (error.code == '42501' ||
          error.message.toLowerCase().contains('row-level security')) {
        // The likely real cause: the offer ended. A technician may message
        // about a job they have been offered, but the moment that match turns
        // `declined` - they said no, or the client chose someone else - the
        // thread stops being theirs.
        throw const RbCarsFailure(
          'This conversation is closed — the job is no longer yours to message about.',
        );
      }
      throw const RbCarsFailure('Could not send that message.');
    } catch (error) {
      _log('send', error);
      throw const RbCarsFailure(
        'Could not send that message. Check your connection.',
      );
    }
  }

  // ---------------------------------------------------------------- photos

  /// Uploads [file] to the private `chat-photos` bucket and posts it as a
  /// message, with [caption] as the body when there is one.
  ///
  /// ## The path is the permission
  ///
  /// Objects are stored as `<job_id>/<uuid>.<ext>`, and the storage policy
  /// reads that first segment back to ask `is_job_participant()`. So the path
  /// is not a convention - it is what makes the photo readable by exactly the
  /// two people on the job and nobody else.
  ///
  /// ## Degrading honestly
  ///
  /// Two things can be missing on a database that has not had migration
  /// `20260923000001_chat_photos` applied: the bucket, and the `image_path`
  /// column. Both are detected and reported as "photo sharing is not set up
  /// yet" rather than as a generic failure, because that names the actual fix.
  Future<ChatMessage> sendPhoto(
    String jobId,
    XFile file, {
    String caption = '',
  }) async {
    final String trimmed = caption.trim();
    if (trimmed.length > 2000) {
      throw const RbCarsFailure('That caption is too long (2000 characters).');
    }

    final Uint8List bytes = await file.readAsBytes();
    if (bytes.lengthInBytes > _maxPhotoBytes) {
      throw const RbCarsFailure(
        'That photo is larger than 5 MB. Try taking it again at a lower '
        'quality.',
      );
    }

    final String extension = _extensionOf(file.name);
    final String path =
        '$jobId/${DateTime.now().millisecondsSinceEpoch}-'
        '${_uid.substring(0, 8)}.$extension';

    try {
      await _client.storage
          .from(_bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: _contentTypeOf(extension),
              upsert: false,
            ),
          );
    } on StorageException catch (error) {
      _log('sendPhoto/upload', error);
      if (_looksLikeMissingBucket(error)) {
        throw const RbCarsFailure(_notSetUp);
      }
      throw const RbCarsFailure(
        'Could not upload that photo. Check your connection and try again.',
      );
    }

    try {
      final Map<String, dynamic> row = await _client
          .from(_table)
          .insert(<String, dynamic>{
            'job_id': jobId,
            'sender_id': _uid,
            'body': trimmed,
            'image_path': path,
          })
          .select()
          .single();

      return ChatMessage.fromJson(row);
    } on PostgrestException catch (error) {
      _log('sendPhoto/insert', error);

      // 42703 is "column does not exist"; PGRST204 is PostgREST's schema-cache
      // version of the same thing.
      if (error.code == '42703' ||
          error.code == 'PGRST204' ||
          error.message.contains('image_path')) {
        throw const RbCarsFailure(_notSetUp);
      }
      if (error.code == '42501' ||
          error.message.toLowerCase().contains('row-level security')) {
        throw const RbCarsFailure(
          'This conversation is closed — the job is no longer yours to message about.',
        );
      }
      throw const RbCarsFailure('Could not send that photo.');
    }
  }

  /// A short-lived signed URL for a stored chat photo.
  ///
  /// Cached in memory for the life of the screen, because a `ListView` asks
  /// for the same bubble's URL every time it scrolls back into view and each
  /// miss would be a round trip. The cache expires well before the URL does,
  /// so a long-lived thread never paints a dead link.
  Future<String> photoUrl(String path) async {
    final _SignedUrl? cached = _signedUrls[path];
    if (cached != null && cached.isFresh) return cached.url;

    final String url = await _client.storage
        .from(_bucket)
        .createSignedUrl(path, _signedUrlSeconds);
    _signedUrls[path] = _SignedUrl(url);
    return url;
  }

  static const String _bucket = 'chat-photos';
  static const int _maxPhotoBytes = 5 * 1024 * 1024;
  static const int _signedUrlSeconds = 3600;

  static const String _notSetUp =
      'Photo sharing is not set up on the server yet. Apply the latest '
      'database migration and try again.';

  final Map<String, _SignedUrl> _signedUrls = <String, _SignedUrl>{};

  static bool _looksLikeMissingBucket(StorageException error) {
    final String text = '${error.statusCode} ${error.message}'.toLowerCase();
    return text.contains('not found') || text.contains('bucket');
  }

  static String _extensionOf(String name) {
    final String lower = name.toLowerCase();
    for (final String candidate in <String>['png', 'webp', 'heic', 'jpeg']) {
      if (lower.endsWith('.$candidate')) return candidate;
    }
    return 'jpg';
  }

  static String _contentTypeOf(String extension) => switch (extension) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    _ => 'image/jpeg',
  };

  /// Marks everything the other person sent as read.
  ///
  /// Never fatal: a failed receipt leaves a badge on screen, which is a far
  /// smaller problem than an error banner over a conversation.
  Future<void> markRead(String jobId) async {
    try {
      await _client.rpc<void>(
        'mark_job_messages_read',
        params: <String, dynamic>{'p_job_id': jobId},
      );
    } catch (error) {
      _log('markRead', error);
    }
  }

  void _log(String action, Object error) {
    if (kDebugMode) {
      if (error is PostgrestException) {
        debugPrint(
          'ChatService.$action failed: [${error.code}] ${error.message}',
        );
      } else {
        debugPrint('ChatService.$action failed: $error');
      }
    }
  }
}

/// A signed storage URL and the moment it was minted.
///
/// Treated as stale well before the hour the server grants, so a thread that
/// has been open a long time refreshes its links rather than painting a
/// bubble whose URL expired thirty seconds ago.
class _SignedUrl {
  _SignedUrl(this.url) : mintedAt = DateTime.now();

  final String url;
  final DateTime mintedAt;

  bool get isFresh =>
      DateTime.now().difference(mintedAt) < const Duration(minutes: 45);
}
