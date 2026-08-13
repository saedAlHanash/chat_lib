import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import '../extensions/chat_extensions.dart';

/// Manages local caching for rooms and messages using Hive CE.
class ChatCacheManager {
  ChatCacheManager._privateConstructor();

  static final ChatCacheManager instance = ChatCacheManager._privateConstructor();

  bool _isInitialized = false;

  /// Initializes Hive CE. Can be passed a custom path or will use the default path for Flutter.
  Future<void> init({String? subDir}) async {
    if (_isInitialized) return;
    await Hive.initFlutter(subDir);
    _isInitialized = true;
  }

  /// Helper to get rooms box name for direct or group rooms.
  String _roomsBoxName(String userId, {bool isGroup = false}) =>
      isGroup ? 'chat_group_rooms_box_$userId' : 'chat_direct_rooms_box_$userId';

  /// Helper to get messages box name for a specific room and user.
  String _messagesBoxName(String roomId, String userId) => 'chat_messages_box_${roomId}_$userId';

  /// Helper to get users box name.
  String get _usersBoxName => 'chat_users_box';

  /// Opens the rooms box for the given [userId] and room category.
  Future<Box<Map>> _openRoomsBox(String userId, {bool isGroup = false}) async {
    await init();
    return Hive.openBox<Map>(_roomsBoxName(userId, isGroup: isGroup));
  }

  /// Opens the messages box for the given [roomId] and [userId].
  Future<Box<Map>> _openMessagesBox(String roomId, String userId) async {
    await init();
    return Hive.openBox<Map>(_messagesBoxName(roomId, userId));
  }

  /// Opens the users cache box.
  Future<Box<Map>> _openUsersBox() async {
    await init();
    return Hive.openBox<Map>(_usersBoxName);
  }

  // --- Rooms Cache Operations ---

  /// Caches a list of rooms for the current user.
  Future<void> saveRooms(String userId, List<types.Room> rooms, {bool isGroup = false}) async {
    final box = await _openRoomsBox(userId, isGroup: isGroup);
    final map = <String, Map>{};
    for (final room in rooms) {
      if (room.shouldHideForUser(userId)) {
        await box.delete(room.id);
      } else {
        map[room.id] = room.toJson();
      }
    }
    if (map.isNotEmpty) {
      await box.putAll(map);
    }
  }

  /// Updates or inserts a single room in the cache.
  Future<void> saveRoom(String userId, types.Room room) async {
    final isGroup = room.type == types.RoomType.group;
    final box = await _openRoomsBox(userId, isGroup: isGroup);
    if (room.shouldHideForUser(userId)) {
      await box.delete(room.id);
    } else {
      await box.put(room.id, room.toJson());
    }
  }

  /// Removes a room from local cache.
  Future<void> deleteRoomFromCache(String userId, String roomId, {bool isGroup = false}) async {
    final box = await _openRoomsBox(userId, isGroup: isGroup);
    await box.delete(roomId);
    await clearRoomMessages(roomId, userId);
  }

  /// Helper to recursively cast Hive dynamic maps to Map<String, dynamic>
  Map<String, dynamic> _deepCastMap(Map map) {
    return map.map((key, value) {
      final stringKey = key.toString();
      if (value is Map) {
        return MapEntry(stringKey, _deepCastMap(value));
      } else if (value is List) {
        return MapEntry(
          stringKey,
          value.map((item) {
            if (item is Map) {
              return _deepCastMap(item);
            }
            return item;
          }).toList(),
        );
      } else {
        return MapEntry(stringKey, value);
      }
    });
  }

  /// Retrieves cached direct (1-to-1) rooms for the current user.
  Future<List<types.Room>> getCachedRooms(String userId) async {
    final box = await _openRoomsBox(userId, isGroup: false);
    final List<types.Room> rooms = [];
    for (final value in box.values) {
      try {
        if (value is Map) {
          final castedMap = _deepCastMap(value);
          final room = types.Room.fromJson(castedMap);
          if (!room.shouldHideForUser(userId)) {
            rooms.add(room);
          }
        }
      } catch (e) {
        // Skip malformed entries
      }
    }

    return rooms
      ..sort((a, b) {
        if (a.isNotRead != b.isNotRead) {
          return a.isNotRead ? -1 : 1;
        }
        return (b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0);
      });
  }

  /// Retrieves cached group session rooms for the current user.
  Future<List<types.Room>> getCachedGroupRooms(String userId) async {
    final box = await _openRoomsBox(userId, isGroup: true);
    final List<types.Room> rooms = [];
    for (final value in box.values) {
      try {
        if (value is Map) {
          final castedMap = _deepCastMap(value);
          final room = types.Room.fromJson(castedMap);
          if (!room.shouldHideForUser(userId)) {
            rooms.add(room);
          }
        }
      } catch (e) {
        print('❌ [getCachedGroupRooms Error]: $e');
      }
    }

    return rooms
      ..sort((a, b) {
        if (a.isNotRead != b.isNotRead) {
          return a.isNotRead ? -1 : 1;
        }
        return (b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0);
      });
  }

  // --- Messages Cache Operations ---

  /// Caches a list of message maps for a specific room and user.
  /// Expects JSON maps of messages.
  Future<void> saveMessages(String roomId, String userId, List<Map<String, dynamic>> messageMaps) async {
    final box = await _openMessagesBox(roomId, userId);
    final map = <String, Map>{};
    for (final msg in messageMaps) {
      final msgId = msg['id']?.toString();
      if (msgId != null) {
        map[msgId] = msg;
      }
    }
    await box.putAll(map);
  }

  /// Updates or inserts a single message in the cache.
  Future<void> saveMessage(String roomId, String userId, Map<String, dynamic> messageMap) async {
    final box = await _openMessagesBox(roomId, userId);
    final msgId = messageMap['id']?.toString();
    if (msgId != null) {
      await box.put(msgId, messageMap);
    }
  }

  /// Retrieves all cached messages for a specific room and user.
  Future<List<types.Message>> getCachedMessages(String roomId, String userId) async {
    final box = await _openMessagesBox(roomId, userId);
    final List<types.Message> messages = [];
    final nowTimeMillis = DateTime.now().millisecondsSinceEpoch;
    final expiredKeys = <String>[];

    for (final key in box.keys) {
      final value = box.get(key);
      try {
        if (value is Map) {
          final castedMap = _deepCastMap(value);
          final type = castedMap['type']?.toString();
          final isDeleted = castedMap['metadata']?['isDeleted'] == true;
          final createdAt = castedMap['createdAt'] is num ? (castedMap['createdAt'] as num).toInt() : 0;

          // Delete files/videos older than a month, or soft deleted messages
          final isOldAttachment = (type == 'file' || type == 'video') &&
              (nowTimeMillis - createdAt).abs() > 2592000000;

          if (isDeleted || isOldAttachment) {
            expiredKeys.add(key.toString());
          } else {
            messages.add(types.Message.fromJson(castedMap));
          }
        }
      } catch (e) {
        // Skip malformed entries
      }
    }

    if (expiredKeys.isNotEmpty) {
      Future(() async {
        for (final k in expiredKeys) {
          await box.delete(k);
        }
      });
    }

    return messages
      ..sort((a, b) => (b.createdAt ?? 0).compareTo(a.createdAt ?? 0));
  }

  /// Clear messages box for a room.
  Future<void> clearRoomMessages(String roomId, String userId) async {
    final box = await _openMessagesBox(roomId, userId);
    await box.clear();
  }

  // --- User Cache Operations ---

  /// Caches a user profile.
  Future<void> cacheUser(types.User user) async {
    final box = await _openUsersBox();
    await box.put(user.id, user.toJson());
  }

  /// Retrieves a cached user profile by ID.
  Future<types.User?> getCachedUser(String userId) async {
    final box = await _openUsersBox();
    final value = box.get(userId);
    if (value == null || value is! Map) return null;
    try {
      final castedMap = _deepCastMap(value);
      return types.User.fromJson(castedMap);
    } catch (e) {
      return null;
    }
  }

// --- Maintenance ---

// /// Clears all local cache for a user (useful on logout).
// Future<void> clearUserCache(String userId) async {
//   final roomsBox = await _openRoomsBox(userId);
//   await roomsBox.clear();
//
//   // Note: Since rooms are deleted, we'd also want to delete individual room message boxes.
//   // We can fetch room IDs and clear them.
//   final rooms = await getCachedRooms(userId, null);
//   for (final room in rooms) {
//     await clearRoomMessages(room.id, userId);
//   }
//
//   final usersBox = await _openUsersBox();
//   await usersBox.clear();
// }
}
