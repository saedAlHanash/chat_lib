import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import '../core/firebase_chat_core.dart';

/// Extension methods for room ID strings.
extension RoomIdExtension on String {
  /// Checks if the room ID represents a numeric group session room.
  bool get isGroupRoomId => RegExp(r'^\d+$').hasMatch(this);

  /// Checks if the room ID represents a direct (1-to-1) room.
  bool get isDirectRoomId => !isGroupRoomId;
}

/// Extension methods for [types.Room] in the chat package.
extension RoomLibExtension on types.Room {
  /// Resolves the current user ID from the core service.
  String get currentUserId => FirebaseChatCore.instance.currentUserId;

  /// Resolves the current user object in the room.
  types.User get me {
    return users.firstWhere((u) => u.id == currentUserId, orElse: () => types.User(id: currentUserId));
  }

  /// Resolves the other user participating in this direct room.
  types.User get otherUser {
    return users.firstWhere(
      (u) => u.id != currentUserId,
      orElse: () => const types.User(id: '-1', firstName: 'Unknown User'),
    );
  }

  /// A concatenation of all users' names in the room.
  String get usersName => users.map((e) => '${e.firstName ?? ''} ${e.lastName ?? ''}'.trim()).join(' ');

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

  /// Checks if room is a group room.
  bool get isGroup => type == types.RoomType.group || id.isGroupRoomId;

  /// Checks if room is a direct (1-on-1) room.
  bool get isDirect => !isGroup;

  /// Checks if a user (defaults to current user) is an admin in this room.
  bool isAdmin([String? targetUserId]) {
    final uid = targetUserId ?? currentUserId;
    final userRoles = metadata?['userRoles'] as Map<String, dynamic>?;
    if (userRoles != null && userRoles[uid] != null) {
      return userRoles[uid] == 'admin';
    }
    final adminId = metadata?['adminId'] as String?;
    if (adminId == uid) return true;
    for (final u in users) {
      if (u.id == uid && u.role == types.Role.admin) return true;
    }
    return false;
  }

  /// Gets permissions map for a target user.
  Map<String, dynamic>? getUserPermissions([String? targetUserId]) {
    final uid = targetUserId ?? currentUserId;
    final permissions = metadata?['userPermissions'] as Map<String, dynamic>?;
    if (permissions != null && permissions[uid] != null) {
      return Map<String, dynamic>.from(permissions[uid]);
    }
    return null;
  }

  /// Checks if a user is allowed to send text messages in this group.
  bool canSendMessages([String? targetUserId]) {
    final perms = getUserPermissions(targetUserId);
    if (perms != null && perms.containsKey('canSendMessages')) {
      return perms['canSendMessages'] == true;
    }
    return true;
  }

  /// Checks if a user is allowed to send media/attachments in this group.
  bool canSendMedia([String? targetUserId]) {
    final perms = getUserPermissions(targetUserId);
    if (perms != null && perms.containsKey('canSendMedia')) {
      return perms['canSendMedia'] == true;
    }
    return true;
  }

  /// Checks if a user is banned from this group.
  bool isBanned([String? targetUserId]) {
    final perms = getUserPermissions(targetUserId);
    if (perms != null && perms.containsKey('isBanned')) {
      return perms['isBanned'] == true;
    }
    return false;
  }

  /// Checks if the entire room is soft-deleted.
  bool get isDeleted => metadata?['isDeleted'] == true;

  /// Checks if a user is marked as removed, left, or inactive in this group.
  bool isUserRemoved([String? targetUserId]) {
    final uid = targetUserId ?? currentUserId;
    final removedUserIds = List<String>.from(metadata?['removedUserIds'] ?? []);
    final outUserIds = List<String>.from(metadata?['outUserIds'] ?? []);
    if (removedUserIds.contains(uid) || outUserIds.contains(uid)) return true;

    final perms = getUserPermissions(uid);
    if (perms != null) {
      if (perms['isRemoved'] == true || perms['isOut'] == true) return true;
    }
    return false;
  }

  /// Determines if this room should be hidden/filtered out for the target user.
  bool shouldHideForUser([String? targetUserId]) {
    final uid = targetUserId ?? currentUserId;
    return isDeleted || isUserRemoved(uid);
  }
}

/// Extension methods for [types.User] in the chat package.
extension UserLibExtension on types.User {
  /// Full name of user.
  String get name => '${firstName ?? ''} ${lastName ?? ''}'.trim();

  /// Email of user from metadata.
  String get email => metadata?['email']?.toString() ?? '';

  /// Checks if user is a trainer or admin.
  bool get isTrainer => metadata?['isTrainer'] == true || role == types.Role.admin;

  /// Checks if user is a guest / placeholder.
  bool get isGuest => firstName?.toLowerCase() == 'guest' || id == '0';
}

/// Extension methods for [types.Message] in the chat package.
extension MessageLibExtension on types.Message {
  /// Checks if the message is soft-deleted.
  bool get isDeleted => metadata?['isDeleted'] == true;

  /// Checks if the message was edited.
  bool get isEdited => metadata?['isEdited'] == true;

  /// Checks if the message was authored by [targetUserId].
  bool isMine(String targetUserId) => author.id == targetUserId;

  /// Checks if message is a text message.
  bool get isTextMessage => type == types.MessageType.text;

  /// Checks if message is an image message.
  bool get isImageMessage => type == types.MessageType.image;

  /// Checks if message is an audio message.
  bool get isAudioMessage => type == types.MessageType.audio;

  /// Checks if message is a file message.
  bool get isFileMessage => type == types.MessageType.file;
}
