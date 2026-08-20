import '../core/firebase_chat_core.dart';

/// Centralized Hive box names and cache keys for Chat Cache.
abstract final class ChatCacheBoxes {
  ChatCacheBoxes._();

  static const String metaBox = 'chat_cache_meta_box';
  static const String usersBox = 'chat_users_box';

  static const String allRoomsKey = 'all_rooms';
  static const String allGroupRoomsKey = 'all_group_rooms';
  static const String versionKey = 'version';

  /// Resolves the provided [userId] or falls back to [FirebaseChatCore.instance.currentUserId].
  static String resolveUserId([String? userId]) =>
      (userId != null && userId.isNotEmpty) ? userId : FirebaseChatCore.instance.currentUserId;

  /// Generates the direct rooms box name for a given user or 'all_rooms'.
  static String directRoomsBox([String? userId]) => 'chat_direct_rooms_box_${resolveUserId(userId)}';

  /// Generates the group rooms box name for a given user or 'all_group_rooms'.
  static String groupRoomsBox([String? userId]) => 'chat_group_rooms_box_${resolveUserId(userId)}';

  /// Generates the messages box name for a specific room.
  static String messagesBox(String roomId) => 'chat_messages_box_$roomId';
}
