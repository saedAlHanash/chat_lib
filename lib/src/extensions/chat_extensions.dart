import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import '../core/firebase_chat_core.dart';

/// Extension methods for [types.Room] in the chat package.
extension RoomLibExtension on types.Room {
  /// Resolves the current user ID from the core service.
  String get currentUserId => FirebaseChatCore.instance.currentUserId;

  /// Resolves the other user participating in this direct room.
  types.User get otherUser {
    return users.firstWhere(
      (u) => u.id != currentUserId,
      orElse: () => const types.User(id: '-1', firstName: 'Unknown User'),
    );
  }

  /// Timestamp of when the current user last viewed the room.
  int get latestSeen => metadata?['latestSeen'] ?? 0;

  /// Online status of the other user in this room.
  bool get isOnline => metadata?['isOnline'] ?? false;

  /// Checks if the room is considered "read" by the current user.
  bool get isRead {
    if ((lastMessages ?? []).isEmpty) return true;
    final latestMessage = lastMessages!.first;
    // The room is read if the latest message was sent by the current user
    // or if the latestSeen timestamp is greater than or equal to the room update time.
    return (latestMessage.author.id == currentUserId) || ((latestSeen - (updatedAt ?? 0)) >= 0);
  }

  /// Checks if the room has unread messages for the current user.
  bool get isNotRead => !isRead;

  /// Checks if the room is a customer support chat (checks if any user ID is '0').
  bool get isSupport => users.any((e) => e.id == '0');
}
