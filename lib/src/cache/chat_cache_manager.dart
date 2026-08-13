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

  /// Helper to get rooms box name for the current user.
  String _roomsBoxName(String userId) => 'chat_rooms_box_$userId';

  /// Helper to get messages box name for a specific room and user.
  String _messagesBoxName(String roomId, String userId) => 'chat_messages_box_${roomId}_$userId';

  /// Helper to get users box name.
  String get _usersBoxName => 'chat_users_box';

  /// Opens the rooms box for the given [userId].
  Future<Box<Map>> _openRoomsBox(String userId) async {
    await init();
    return Hive.openBox<Map>(_roomsBoxName(userId));
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
  Future<void> saveRooms(String userId, List<types.Room> rooms) async {
    final box = await _openRoomsBox(userId);
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
    final box = await _openRoomsBox(userId);
    if (room.shouldHideForUser(userId)) {
      await box.delete(room.id);
    } else {
      await box.put(room.id, room.toJson());
    }
  }

  /// Removes a room from local cache.
  Future<void> deleteRoomFromCache(String userId, String roomId) async {
    final box = await _openRoomsBox(userId);
    await box.delete(roomId);
    await clearRoomMessages(roomId, userId);
  }

  /// Retrieves all cached rooms for the current user (filters out deleted or removed rooms).
  Future<List<types.Room>> getCachedRooms(String userId, types.RoomType roomType) async {
    final box = await _openRoomsBox(userId);
    final List<types.Room> rooms = [];
    for (final value in box.values) {
      try {
        final castedMap = Map<String, dynamic>.from(value);
        final room = types.Room.fromJson(castedMap);
        if (!room.shouldHideForUser(userId)) {
          if (room.type == roomType) {
            rooms.add(room);
          }
        }
      } catch (e) {
        // Skip malformed entries
      }
    }

    // Sort rooms by updatedAt descending (newest first)
    return rooms..sort((a, b) {
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
    for (final value in box.values) {
      try {
        final castedMap = Map<String, dynamic>.from(value);
        messages.add(types.Message.fromJson(castedMap));
      } catch (e) {
        // Skip malformed entries
      }
    }
    return messages;
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
    if (value == null) return null;
    try {
      final castedMap = Map<String, dynamic>.from(value);
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
