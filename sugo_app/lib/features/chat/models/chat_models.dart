import 'dart:typed_data';

import '../../rb_cars/models/job_enums.dart';

/// One message in a job thread.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.jobId,
    required this.senderId,
    required this.body,
    required this.createdAt,
    this.imagePath,
    this.readAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      jobId: json['job_id'] as String,
      senderId: json['sender_id'] as String,
      body: json['body'] as String? ?? '',
      // Absent on a build whose database has not had the chat-photos
      // migration applied, which is exactly why it is read defensively.
      imagePath: json['image_path'] as String?,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      readAt: DateTime.tryParse(json['read_at'] as String? ?? '')?.toLocal(),
    );
  }

  final String id;
  final String jobId;
  final String senderId;
  final String body;

  /// Object path inside the private `chat-photos` bucket, or null for a
  /// text-only message. Never a URL: the bucket is private, so the screen
  /// exchanges this for a short-lived signed URL when it draws the bubble.
  final String? imagePath;

  final DateTime createdAt;

  /// Set when the recipient opened the thread. Only ever written by the
  /// recipient - the database guard refuses a sender marking their own
  /// message read, which is what keeps a read receipt meaningful.
  final DateTime? readAt;

  bool get isRead => readAt != null;

  bool get hasImage => (imagePath ?? '').isNotEmpty;

  /// True for a photo sent without a caption, which the bubble draws as a
  /// picture with nothing under it.
  bool get isPhotoOnly => hasImage && body.trim().isEmpty;

  /// True when this message was sent by [userId], which decides which side of
  /// the thread it renders on.
  bool isMine(String? userId) => userId != null && senderId == userId;
}

/// A message that has been typed but not yet acknowledged by the server.
///
/// Rendered immediately, greyed, so the thread feels responsive on a slow
/// connection - and replaced by the real row when the insert returns. Without
/// this the bubble appears a second after you press send, which reads as the
/// app having dropped it.
class PendingMessage {
  PendingMessage({
    required this.localId,
    required this.body,
    this.failed = false,
    this.imageBytes,
    this.uploading = false,
  });

  final String localId;
  final String body;

  /// Set when the send failed. The bubble then offers a retry rather than
  /// silently vanishing, which is the worst thing a chat can do.
  final bool failed;

  /// The picked photo, already read into memory so the bubble can draw it
  /// before the upload finishes - and on web, where there is no `File`.
  final Uint8List? imageBytes;

  /// True while the bytes are on their way to storage, which the bubble shows
  /// as a progress veil over the picture.
  final bool uploading;

  bool get hasImage => imageBytes != null;

  PendingMessage copyWith({bool? failed, bool? uploading}) => PendingMessage(
    localId: localId,
    body: body,
    failed: failed ?? this.failed,
    imageBytes: imageBytes,
    uploading: uploading ?? this.uploading,
  );
}

/// A row of `job_conversations`: one job the caller can chat about.
class Conversation {
  const Conversation({
    required this.jobId,
    required this.counterpartName,
    required this.jobStatus,
    required this.deviceType,
    required this.problemSymptom,
    this.counterpartId,
    this.counterpartAvatarUrl,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.isPendingOffer = false,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    // `counterpart` is a jsonb object built by `profile_display()`, because
    // `profiles` is readable only by its owner - a plain join would have left
    // the other person's name null for everybody.
    final Map<String, dynamic> counterpart =
        (json['counterpart'] as Map<String, dynamic>?) ?? <String, dynamic>{};

    return Conversation(
      jobId: json['job_id'] as String,
      counterpartId: counterpart['id'] as String?,
      counterpartName:
          (counterpart['full_name'] as String?)?.trim().isNotEmpty ?? false
          ? counterpart['full_name'] as String
          : 'SUGO user',
      counterpartAvatarUrl: counterpart['avatar_url'] as String?,
      jobStatus: JobStatus.fromWire(json['job_status'] as String?),
      deviceType: json['device_type'] as String? ?? '',
      problemSymptom: json['problem_symptom'] as String? ?? '',
      lastMessage: json['last_message'] as String?,
      lastMessageAt: DateTime.tryParse(
        json['last_message_at'] as String? ?? '',
      )?.toLocal(),
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      // Added by 20260923000003. Read defensively so a build newer than the
      // database still lists conversations.
      isPendingOffer: json['is_pending_offer'] as bool? ?? false,
    );
  }

  final String jobId;
  final String? counterpartId;
  final String counterpartName;
  final String? counterpartAvatarUrl;
  final JobStatus jobStatus;
  final String deviceType;
  final String problemSymptom;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;

  /// True while this is a negotiation with a technician who has been asked
  /// but has not accepted. The row says so, because "we are still talking
  /// about the price" and "this person is coming on Thursday" are two very
  /// different things to have in an inbox.
  final bool isPendingOffer;

  bool get hasUnread => unreadCount > 0;

  /// What the row shows under the name. Falls back to the job itself, so a
  /// brand-new thread is not a blank line.
  String get preview {
    final String? last = lastMessage?.trim();
    if (last != null && last.isNotEmpty) return last;
    return 'No messages yet — say hello';
  }

  String get initials {
    final String name = counterpartName.trim();
    if (name.isEmpty) return '?';
    final List<String> parts = name.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}
