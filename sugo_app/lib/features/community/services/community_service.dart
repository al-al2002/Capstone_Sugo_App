import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../models/community_models.dart';

/// Reads and writes the Community feed.
///
/// ## Why every call is a plain table operation
///
/// Same reasoning as `ChatService`: nothing here needs elevated privilege.
/// The policies in migration 20260921000001 already answer every question that
/// matters - who may ask, who may answer, who may vote - and they answer it
/// from the caller's own role. An edge function would add a hop and a second
/// place for those rules to live.
///
/// The one thing worth noticing is what this class *cannot* do: there is no
/// method to write reputation. Points are maintained entirely by database
/// triggers, so the app has no way to award them even if a future screen tried
/// to. That is the whole reason a points economy stays honest.
class CommunityService {
  CommunityService({SupabaseClient? client}) : _injected = client;

  final SupabaseClient? _injected;

  /// Resolved per call rather than in the constructor.
  ///
  /// Same reasoning as `RbCarsService`: `Supabase.instance` throws until
  /// `Supabase.initialize` has run, so resolving eagerly meant that merely
  /// *constructing* this service - which every community screen does in a
  /// field initializer - required a live backend. Widget tests could not pump
  /// the feed or the composer at all. Deferring costs one null check and makes
  /// the screens renderable offline; the throw still happens, just at the call
  /// that actually needs the network.
  SupabaseClient get _client => _injected ?? SupabaseService.client;

  static const String _feed = 'community_feed';
  static const String _thread = 'community_thread';
  static const String _posts = 'community_posts';
  static const String _comments = 'community_comments';
  static const String _votes = 'community_votes';

  String? get currentUserId => _client.auth.currentUser?.id;

  String get _uid {
    final String? id = currentUserId;
    if (id == null) {
      throw const RbCarsFailure('Please sign in again to continue.');
    }
    return id;
  }

  // ------------------------------------------------------------------ feed

  /// The feed, ordered and optionally filtered by topic.
  ///
  /// "Most Helpful" sorts by total helpful votes across the thread and breaks
  /// ties on recency. Without the tie-break, every unanswered question - all
  /// of them on zero - would come back in whatever order Postgres felt like,
  /// and the feed would reshuffle itself on each refresh.
  Future<List<CommunityPost>> feed({
    CommunitySort sort = CommunitySort.recent,
    CommunityTopic? topic,
    int limit = 50,
  }) async {
    try {
      PostgrestFilterBuilder<List<Map<String, dynamic>>> query = _client
          .from(_feed)
          .select();

      if (topic != null) {
        query = query.eq('topic', topic.wire);
      }

      final List<Map<String, dynamic>> rows = switch (sort) {
        CommunitySort.recent => await query
            .order('last_activity_at', ascending: false)
            .limit(limit),
        CommunitySort.mostHelpful => await query
            .order('helpful_total', ascending: false)
            .order('last_activity_at', ascending: false)
            .limit(limit),
      };

      return rows.map(CommunityPost.fromJson).toList(growable: false);
    } on PostgrestException catch (error) {
      _log('feed', error);
      throw const RbCarsFailure('Could not load the community feed.');
    } catch (error) {
      _log('feed', error);
      throw const RbCarsFailure(
        'Could not load the community feed. Check your connection.',
      );
    }
  }

  /// One question, re-read after it is answered.
  Future<CommunityPost?> post(String postId) async {
    try {
      final Map<String, dynamic>? row = await _client
          .from(_feed)
          .select()
          .eq('id', postId)
          .maybeSingle();

      return row == null ? null : CommunityPost.fromJson(row);
    } on PostgrestException catch (error) {
      _log('post', error);
      throw const RbCarsFailure('Could not load that question.');
    }
  }

  /// Asks a question. Clients only - the insert policy enforces it.
  ///
  /// [photo] is optional, and deliberately so. A picture of the fault answers
  /// questions the asker does not know how to put into words - a swollen
  /// battery, a burn mark, an error code on a screen - but requiring one would
  /// block the many questions that are about advice rather than a symptom.
  Future<CommunityPost> ask({
    required String title,
    required String body,
    CommunityTopic topic = CommunityTopic.general,
    XFile? photo,
  }) async {
    final String cleanTitle = title.trim();
    final String cleanBody = body.trim();

    // Checked here as well as in the column constraints, so the user gets a
    // sentence rather than a Postgres violation.
    if (cleanTitle.length < 8) {
      throw const RbCarsFailure(
        'Give your question a title of at least 8 characters.',
      );
    }
    if (cleanTitle.length > 160) {
      throw const RbCarsFailure('That title is too long (160 characters).');
    }
    if (cleanBody.length < 10) {
      throw const RbCarsFailure(
        'Add a little more detail so a technician can answer.',
      );
    }
    if (cleanBody.length > 4000) {
      throw const RbCarsFailure('That question is too long (4000 characters).');
    }

    // ---------------------------------------------------------- the photo
    //
    // Uploaded *before* the row, so a failed upload costs nothing: the user
    // sees "could not upload" with their draft still in front of them, rather
    // than a posted question they now have to edit or delete. The reverse
    // order would trade one recoverable error for an unrecoverable one.
    final String? imagePath = photo == null ? null : await _uploadPhoto(photo);

    // ---------------------------------------------------------- the write
    //
    // On its own, and the only part allowed to fail the call. Everything after
    // this point is enrichment of a question that is already saved.
    final String postId;
    try {
      final Map<String, dynamic> row = await _client
          .from(_posts)
          .insert(<String, dynamic>{
            'author_id': _uid,
            'title': cleanTitle,
            'body': cleanBody,
            'topic': topic.wire,
            if (imagePath != null) 'image_path': imagePath,
          })
          .select('id')
          .single();

      postId = row['id'] as String;
    } on PostgrestException catch (error) {
      _log('ask', error);

      // 42703 is "column does not exist"; PGRST204 is PostgREST's schema-cache
      // version of the same. Both mean the photo migration has not been
      // applied, which is worth naming rather than reporting as a generic
      // failure - the fix is one command.
      if (imagePath != null &&
          (error.code == '42703' ||
              error.code == 'PGRST204' ||
              error.message.contains('image_path'))) {
        throw const RbCarsFailure(_photosNotSetUp);
      }

      throw RbCarsFailure(_writeFailure(error, 'post a question'), detail: error);
    } catch (error) {
      _log('ask', error);
      throw const RbCarsFailure(
        'Could not post your question. Check your connection.',
      );
    }

    // ------------------------------------------------------- the read-back
    //
    // Best effort, and deliberately never fatal.
    //
    // This used to sit inside the same `try` as the insert, and it threw when
    // it came back empty. That produced the worst possible outcome: the
    // question **was** saved, but the composer stayed open showing an error,
    // so it never closed, so the feed never refreshed - and the user was told
    // their question failed while looking at a feed that did not show the
    // question they had just successfully posted.
    //
    // The read-back only exists to resolve the author so the new row renders
    // with a name instead of "SUGO user" for a second. That is worth a request
    // and worth exactly zero errors.
    try {
      final CommunityPost? stored = await post(postId);
      if (stored != null) return stored;
    } catch (error) {
      _log('ask.readback', error);
    }

    // The question is in the database; the caller refreshes the feed
    // immediately, which replaces this with the fully resolved row.
    return CommunityPost(
      id: postId,
      title: cleanTitle,
      body: cleanBody,
      topic: topic,
      author: CommunityAuthor.unknown,
      isMine: true,
      imagePath: imagePath,
      createdAt: DateTime.now(),
      lastActivityAt: DateTime.now(),
    );
  }

  // ---------------------------------------------------------------- photos

  static const String _photoBucket = 'community-photos';
  static const int _maxPhotoBytes = 5 * 1024 * 1024;

  static const String _photosNotSetUp =
      'Photos on community questions are not set up on the server yet. Apply '
      'the latest database migration and try again.';

  /// Uploads a question's photo and returns its object path.
  ///
  /// ## Why the path starts with the author's id
  ///
  /// The storage insert policy checks that first segment against `auth.uid()`.
  /// So, exactly as with chat photos, the path is not a filing convention -
  /// it is the rule that stops one user writing into another's folder. The
  /// difference is what happens afterwards: this bucket is public-read,
  /// because the question it belongs to is public too.
  Future<String> _uploadPhoto(XFile photo) async {
    final Uint8List bytes = await photo.readAsBytes();
    if (bytes.lengthInBytes > _maxPhotoBytes) {
      throw const RbCarsFailure(
        'That photo is larger than 5 MB. Try taking it again at a lower '
        'quality.',
      );
    }

    final String extension = _extensionOf(photo.name);
    final String path =
        '$_uid/${DateTime.now().millisecondsSinceEpoch}.$extension';

    try {
      await _client.storage
          .from(_photoBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: _contentTypeOf(extension),
              upsert: false,
            ),
          );
      return path;
    } on StorageException catch (error) {
      _log('ask/upload', error);

      final String text = '${error.statusCode} ${error.message}'.toLowerCase();
      if (text.contains('not found') || text.contains('bucket')) {
        throw const RbCarsFailure(_photosNotSetUp);
      }
      throw const RbCarsFailure(
        'Could not upload that photo. Check your connection and try again.',
      );
    }
  }

  /// The public URL for a stored question photo, or null when there is none.
  ///
  /// No signing, unlike `ChatService.photoUrl`: the bucket is public, so this
  /// is pure string building and needs no round trip. That is what lets the
  /// feed render thumbnails while scrolling, and why it can be static - a
  /// card does not need a service instance to show a picture.
  ///
  /// Null rather than a throw when Supabase has not been initialised, which
  /// is every widget test. A thumbnail is decoration; failing to build one
  /// must not take the feed down with it.
  static String? publicPhotoUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    try {
      return SupabaseService.client.storage
          .from(_photoBucket)
          .getPublicUrl(path);
    } catch (_) {
      return null;
    }
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

  Future<void> deletePost(String postId) async {
    try {
      await _client.from(_posts).delete().eq('id', postId);
    } on PostgrestException catch (error) {
      _log('deletePost', error);
      throw const RbCarsFailure('Could not delete that question.');
    }
  }

  // ---------------------------------------------------------------- thread

  /// Answers on a post.
  ///
  /// "Most Helpful" is the default here, unlike the feed. Within a thread the
  /// reader wants the best answer, not the newest one - and an accepted-wisdom
  /// answer sinking below a late "same problem here" is the failure mode every
  /// Q&A site is judged on.
  Future<List<CommunityAnswer>> answers(
    String postId, {
    CommunitySort sort = CommunitySort.mostHelpful,
  }) async {
    try {
      final PostgrestFilterBuilder<List<Map<String, dynamic>>> query = _client
          .from(_thread)
          .select()
          .eq('post_id', postId);

      final List<Map<String, dynamic>> rows = switch (sort) {
        CommunitySort.recent => await query.order('created_at'),
        CommunitySort.mostHelpful => await query
            .order('helpful_count', ascending: false)
            .order('created_at'),
      };

      return rows.map(CommunityAnswer.fromJson).toList(growable: false);
    } on PostgrestException catch (error) {
      _log('answers', error);
      throw const RbCarsFailure('Could not load the answers.');
    }
  }

  /// Posts an answer.
  ///
  /// `author_role` is read from the session's profile rather than asserted by
  /// the caller, and the insert policy checks it against the same source. A
  /// client cannot post an answer badged as a technician.
  Future<void> answer({required String postId, required String body}) async {
    final String clean = body.trim();

    if (clean.length < 2) {
      throw const RbCarsFailure('Write an answer first.');
    }
    if (clean.length > 4000) {
      throw const RbCarsFailure('That answer is too long (4000 characters).');
    }

    try {
      final String role = await _role();

      await _client.from(_comments).insert(<String, dynamic>{
        'post_id': postId,
        'author_id': _uid,
        'author_role': role,
        'body': clean,
      });
    } on PostgrestException catch (error) {
      _log('answer', error);
      throw RbCarsFailure(_writeFailure(error, 'post an answer'));
    }
  }

  Future<void> deleteAnswer(String answerId) async {
    try {
      await _client.from(_comments).delete().eq('id', answerId);
    } on PostgrestException catch (error) {
      _log('deleteAnswer', error);
      throw const RbCarsFailure('Could not delete that answer.');
    }
  }

  // ----------------------------------------------------------------- votes

  /// Marks an answer helpful, or takes the vote back.
  ///
  /// The vote itself is the whole record - there is no score column - so
  /// casting is an insert and withdrawing is a delete. The database trigger
  /// re-tallies the comment and the author's reputation either way.
  Future<void> setHelpful({
    required String answerId,
    required bool helpful,
  }) async {
    try {
      if (helpful) {
        await _client.from(_votes).insert(<String, dynamic>{
          'comment_id': answerId,
          'voter_id': _uid,
        });
      } else {
        await _client
            .from(_votes)
            .delete()
            .eq('comment_id', answerId)
            .eq('voter_id', _uid);
      }
    } on PostgrestException catch (error) {
      // A duplicate key means the vote was already there - the user
      // double-tapped, or a stale row disagreed with the server. The end
      // state is the one they asked for, so this is not worth an error.
      if (error.code == '23505') return;

      _log('setHelpful', error);

      if (_isPolicyViolation(error)) {
        throw const RbCarsFailure(
          'Only clients can rate a technician’s answer.',
        );
      }
      throw const RbCarsFailure('Could not save your rating.');
    }
  }

  // ---------------------------------------------------------------- unread

  /// Community activity the caller has not seen, for the nav badge.
  ///
  /// Role-aware, and the database decides which meaning applies: new answers
  /// on your own questions if you are a client, new unanswered questions if
  /// you are a technician. See migration 20260921000004 for why those are not
  /// the same number.
  ///
  /// Never fatal, and never an error on screen. A badge is decoration; failing
  /// to load one must not put a banner over a working dashboard.
  Future<int> unreadCount() async {
    try {
      // Read as `num`, not `int`. PostgREST returns a bare JSON number for a
      // scalar function, and pinning the generic to `int` makes this a cast
      // that throws if it ever decodes as a double - which my own catch would
      // then swallow, leaving a badge that silently never appears. A `num`
      // cast cannot fail on either.
      final Object? raw = await _client.rpc<Object?>('community_unread_count');
      return (raw as num?)?.toInt() ?? 0;
    } catch (error) {
      _log('unreadCount', error);
      return 0;
    }
  }

  /// Stamps the caller's watermark, clearing the badge.
  ///
  /// Called when the Community tab is opened. The timestamp is always `now()`
  /// on the server - it is never sent from here - so the badge cannot be
  /// cleared for a moment the caller has not actually reached.
  Future<void> markSeen() async {
    try {
      await _client.rpc<void>('mark_community_seen');
    } catch (error) {
      // A failed watermark leaves a badge on screen, which is a far smaller
      // problem than an error over the feed the user just opened.
      _log('markSeen', error);
    }
  }

  // ------------------------------------------------------------ reputation

  /// A technician's community standing, for their profile screen.
  ///
  /// Returns zeros rather than throwing when there is no row: a technician who
  /// has never answered has no reputation row, and that is a normal state, not
  /// an error to put over their profile.
  Future<({int points, int helpfulVotes, int answers})> reputation(
    String technicianId,
  ) async {
    try {
      final Map<String, dynamic>? row = await _client
          .from('community_reputation')
          .select()
          .eq('technician_id', technicianId)
          .maybeSingle();

      if (row == null) {
        return (points: 0, helpfulVotes: 0, answers: 0);
      }

      return (
        points: (row['points'] as num?)?.toInt() ?? 0,
        helpfulVotes: (row['helpful_votes'] as num?)?.toInt() ?? 0,
        answers: (row['answers'] as num?)?.toInt() ?? 0,
      );
    } catch (error) {
      _log('reputation', error);
      return (points: 0, helpfulVotes: 0, answers: 0);
    }
  }

  // ---------------------------------------------------------------- shared

  /// The caller's role, for stamping an answer.
  Future<String> _role() async {
    try {
      final Map<String, dynamic>? row = await _client
          .from('profiles')
          .select('role')
          .eq('id', _uid)
          .maybeSingle();

      return row?['role'] as String? ?? 'client';
    } catch (error) {
      _log('_role', error);
      // The insert policy re-checks this against the same source, so a wrong
      // guess here fails the write rather than forging a badge.
      return 'client';
    }
  }

  bool _isPolicyViolation(PostgrestException error) =>
      error.code == '42501' ||
      error.message.toLowerCase().contains('row-level security');

  /// Turns a write failure into something worth reading.
  String _writeFailure(PostgrestException error, String action) {
    if (_isPolicyViolation(error)) {
      return action == 'post a question'
          // The most likely real cause, and worth naming: the feed is a place
          // where questions come from clients.
          ? 'Only clients can post a question. Technicians answer them.'
          : 'You are not allowed to $action here.';
    }
    if (error.code == '23514') {
      return 'That does not look right — check the length and try again.';
    }
    return 'Could not $action. Check your connection.';
  }

  void _log(String action, Object error) {
    if (kDebugMode) {
      if (error is PostgrestException) {
        debugPrint(
          'CommunityService.$action failed: [${error.code}] ${error.message}',
        );
      } else {
        debugPrint('CommunityService.$action failed: $error');
      }
    }
  }
}
