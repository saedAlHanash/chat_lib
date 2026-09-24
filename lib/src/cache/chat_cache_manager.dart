import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'chat_cache_boxes.dart';
import '../extensions/chat_extensions.dart';

/// Manages local caching for rooms and messages using Hive CE.
class ChatCacheManager {
  ChatCacheManager._privateConstructor();

  static final ChatCacheManager instance = ChatCacheManager._privateConstructor();

  static const int defaultCacheVersion = 1;
  bool _isInitialized = false;
  Completer<void>? _initCompleter;

  /// Initializes Hive CE and validates cache version.
  /// If the cache version changed, purges all old cache and starts fresh.
  /// Automatically seeds initial data per box if the box is currently empty.
  Future<void> init({
    String? subDir,
    int? version,
    String? directRoomsSeedAssetPath,
    String? groupRoomsSeedAssetPath,
    String? usersSeedAssetPath,
    String directRoomsKey = ChatCacheBoxes.allRoomsKey,
    String groupRoomsKey = ChatCacheBoxes.allGroupRoomsKey,
  }) async {
    if (_isInitialized) return;
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }
    _initCompleter = Completer<void>();

    try {
      await Hive.initFlutter(subDir);

      final targetVersion = version ?? defaultCacheVersion;
      final metaBox = await Hive.openBox<dynamic>(ChatCacheBoxes.metaBox);
      final storedVersion = metaBox.get(ChatCacheBoxes.versionKey);
      final bool isVersionChanged = storedVersion == null || storedVersion != targetVersion;

      if (isVersionChanged) {
        await purgeAllCache();
        final newMetaBox = await Hive.openBox<dynamic>(ChatCacheBoxes.metaBox);
        await newMetaBox.put(ChatCacheBoxes.versionKey, targetVersion);

        if (usersSeedAssetPath != null || directRoomsSeedAssetPath != null || groupRoomsSeedAssetPath != null) {
          await seedFromConfig(
            usersSeedAssetPath: usersSeedAssetPath,
            directRoomsSeedAssetPath: directRoomsSeedAssetPath,
            groupRoomsSeedAssetPath: groupRoomsSeedAssetPath,
            directRoomsKey: directRoomsKey,
            groupRoomsKey: groupRoomsKey,
            force: true,
          );
        }
      }

      _isInitialized = true;
      _initCompleter!.complete();
    } catch (e, st) {
      _initCompleter!.completeError(e, st);
      _initCompleter = null;
      rethrow;
    }
  }

  /// Purges all local chat cache from disk.
  Future<void> purgeAllCache() async {
    try {
      await Hive.deleteFromDisk();
    } catch (_) {}
  }

  /// Opens the direct rooms box for the given [userId] or current user.
  Future<Box<Map>> _openDirectRoomsBox([String? userId]) async {
    await init();
    return Hive.openBox<Map>(ChatCacheBoxes.directRoomsBox(userId));
  }

  /// Opens the group rooms box for the given [userId] or current user.
  Future<Box<Map>> _openGroupRoomsBox([String? userId]) async {
    await init();
    return Hive.openBox<Map>(ChatCacheBoxes.groupRoomsBox(userId));
  }

  /// Opens the messages box for the given [roomId].
  Future<Box<Map>> _openMessagesBox(String roomId) async {
    await init();
    return Hive.openBox<Map>(ChatCacheBoxes.messagesBox(roomId));
  }

  /// Opens the users cache box.
  Future<Box<Map>> _openUsersBox() async {
    await init();
    return Hive.openBox<Map>(ChatCacheBoxes.usersBox);
  }

  /// Seeds all data from configured asset paths if caches are empty or need merge.
  Future<void> seedFromConfig({
    String? usersSeedAssetPath,
    String? directRoomsSeedAssetPath,
    String? groupRoomsSeedAssetPath,
    String directRoomsKey = ChatCacheBoxes.allRoomsKey,
    String groupRoomsKey = ChatCacheBoxes.allGroupRoomsKey,
    bool force = false,
    void Function(String step, double progress)? onProgress,
  }) async {
    await init();

    if (usersSeedAssetPath != null && usersSeedAssetPath.isNotEmpty) {
      onProgress?.call('مزامنة المستخدمين...', 0.2);
      await seedUsersFromAsset(usersSeedAssetPath, force: force);
    }
    if (directRoomsSeedAssetPath != null && directRoomsSeedAssetPath.isNotEmpty) {
      onProgress?.call('مزامنة المحادثات المباشرة...', 0.6);
      await seedDirectRoomsFromAsset(directRoomsSeedAssetPath, userId: directRoomsKey, force: force);
    }
    if (groupRoomsSeedAssetPath != null && groupRoomsSeedAssetPath.isNotEmpty) {
      onProgress?.call('مزامنة المجموعات...', 0.9);
      await seedGroupRoomsFromAsset(groupRoomsSeedAssetPath, userId: groupRoomsKey, force: force);
    }
    onProgress?.call('اكتملت المزامنة', 1.0);
  }

  // --- Individual Seed Operations ---

  /// Seeds users from an asset file. Merges if box is empty, force is true, or box.length < map.length.
  Future<void> seedUsersFromAsset(String assetPath, {bool force = false}) async {
    try {
      final box = await Hive.openBox<Map>(ChatCacheBoxes.usersBox);
      final jsonStr = await rootBundle.loadString(assetPath);
      final map = await compute(_parseUsersSeedJson, jsonStr);
      if (map.isNotEmpty) {
        if (box.isEmpty || force || box.length < map.length) {
          if (force) await box.clear();
          await box.putAll(map);
        }
      }
    } catch (e) {
      print('⚠️ [ChatCacheManager seedUsersFromAsset error]: $e');
    }
  }

  /// Seeds direct rooms from an asset file. Merges if box is empty, force is true, or box.length < map.length.
  Future<void> seedDirectRoomsFromAsset(String assetPath, {String userId = ChatCacheBoxes.allRoomsKey, bool force = false}) async {
    try {
      final box = await Hive.openBox<Map>(ChatCacheBoxes.directRoomsBox(userId));
      final usersBox = await _openUsersBox();
      final usersMap = Map<String, Map>.from(usersBox.toMap());

      final jsonStr = await rootBundle.loadString(assetPath);
      final map = await compute(_parseAndHydrateRoomsJson, _RoomHydratePayload(jsonStr: jsonStr, usersMap: usersMap));

      if (map.isNotEmpty) {
        if (box.isEmpty || force || box.length < map.length) {
          if (force) await box.clear();
          await box.putAll(map);
        }
      }
    } catch (e) {
      print('⚠️ [ChatCacheManager seedDirectRoomsFromAsset error]: $e');
    }
  }

  /// Seeds group rooms from an asset file. Merges if box is empty, force is true, or box.length < map.length.
  Future<void> seedGroupRoomsFromAsset(String assetPath, {String userId = ChatCacheBoxes.allGroupRoomsKey, bool force = false}) async {
    try {
      final box = await Hive.openBox<Map>(ChatCacheBoxes.groupRoomsBox(userId));
      final usersBox = await _openUsersBox();
      final usersMap = Map<String, Map>.from(usersBox.toMap());

      final jsonStr = await rootBundle.loadString(assetPath);
      final map = await compute(_parseAndHydrateRoomsJson, _RoomHydratePayload(jsonStr: jsonStr, usersMap: usersMap));

      if (map.isNotEmpty) {
        if (box.isEmpty || force || box.length < map.length) {
          if (force) await box.clear();
          await box.putAll(map);
        }
      }
    } catch (e) {
      print('⚠️ [ChatCacheManager seedGroupRoomsFromAsset error]: $e');
    }
  }

  /// Checks if cache needs sync (e.g. users box is empty)
  Future<bool> isCacheEmpty() async {
    await init();
    final usersBox = await _openUsersBox();
    return usersBox.isEmpty;
  }

  // --- Export Operations ---

  /// Compresses a room map for export by converting `users` list to pure string IDs.
  Map<String, dynamic> _compressRoomForExport(Map roomMap) {
    final map = _deepCastMap(roomMap);
    if (map['users'] is List) {
      map['users'] = (map['users'] as List).map((u) {
        if (u is Map && u['id'] != null) {
          return u['id'].toString();
        }
        return u.toString();
      }).toList();
    }
    return map;
  }

  /// Exports all cached direct rooms, group rooms, and users as individual JSON files into a directory.
  Future<Map<String, String>> exportAllSeedFiles(
    String directoryPath, {
    String directRoomsKey = ChatCacheBoxes.allRoomsKey,
    String groupRoomsKey = ChatCacheBoxes.allGroupRoomsKey,
    bool pretty = true,
  }) async {
    final dir = Directory(directoryPath);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final encoder = JsonEncoder.withIndent(pretty ? '  ' : null);

    final directRoomsBox = await _openDirectRoomsBox(directRoomsKey);
    final groupRoomsBox = await _openGroupRoomsBox(groupRoomsKey);
    final usersBox = await _openUsersBox();

    final directPath = '$directoryPath/direct_rooms_seed.json';
    final groupPath = '$directoryPath/group_rooms_seed.json';
    final usersPath = '$directoryPath/users_seed.json';

    final directRooms = directRoomsBox.values.map((v) => _compressRoomForExport(v)).toList();
    final groupRooms = groupRoomsBox.values.map((v) => _compressRoomForExport(v)).toList();
    final users = usersBox.values.map((v) => _deepCastMap(v)).toList();

    await File(directPath).writeAsString(encoder.convert(directRooms));
    await File(groupPath).writeAsString(encoder.convert(groupRooms));
    await File(usersPath).writeAsString(encoder.convert(users));

    return {'directRooms': directPath, 'groupRooms': groupPath, 'users': usersPath};
  }

  // --- Direct Rooms Cache Operations ---

  /// Caches a list of direct rooms for the user.
  Future<void> saveDirectRooms(List<types.Room> rooms, {String? userId}) async {
    final box = await _openDirectRoomsBox(userId);
    final targetUserId = ChatCacheBoxes.resolveUserId(userId);
    final map = <String, Map>{};
    for (final room in rooms) {
      if (room.shouldHideForUser(targetUserId)) {
        await box.delete(room.id);
      } else {
        map[room.id] = room.toJson();
      }
    }
    if (map.isNotEmpty) {
      await box.putAll(map);
    }
  }

  /// Updates or inserts a single direct room in the cache.
  Future<void> saveDirectRoom(types.Room room, {String? userId}) async {
    final box = await _openDirectRoomsBox(userId);
    final targetUserId = ChatCacheBoxes.resolveUserId(userId);
    if (room.shouldHideForUser(targetUserId)) {
      await box.delete(room.id);
    } else {
      await box.put(room.id, room.toJson());
    }
  }

  /// Removes a direct room from local cache.
  Future<void> deleteDirectRoomFromCache(String roomId, {String? userId}) async {
    final box = await _openDirectRoomsBox(userId);
    await box.delete(roomId);
    await clearRoomMessages(roomId);
  }

  /// Retrieves cached direct (1-to-1) rooms for the user.
  Future<List<types.Room>> getCachedDirectRooms({String? userId}) async {
    final box = await _openDirectRoomsBox(userId);
    final targetUserId = ChatCacheBoxes.resolveUserId(userId);
    final List<types.Room> rooms = [];
    for (final value in box.values) {
      try {
        final castedMap = _deepCastMap(value);
        _sanitizeRoomMap(castedMap);
        final room = types.Room.fromJson(castedMap);
        if (!room.shouldHideForUser(targetUserId)) {
          rooms.add(room);
        }
      } catch (e, st) {
        print('❌ [getCachedDirectRooms Error]: $e \n$st\n$value');
      }
    }

    return rooms..sort((a, b) {
      if (a.isNotRead != b.isNotRead) {
        return a.isNotRead ? -1 : 1;
      }
      return (b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0);
    });
  }

  // --- Group Rooms Cache Operations ---

  /// Caches a list of group rooms for the user.
  Future<void> saveGroupRooms(List<types.Room> rooms, {String? userId}) async {
    final box = await _openGroupRoomsBox(userId);
    final targetUserId = ChatCacheBoxes.resolveUserId(userId);
    final map = <String, Map>{};
    for (final room in rooms) {
      if (room.shouldHideForUser(targetUserId)) {
        await box.delete(room.id);
      } else {
        map[room.id] = room.toJson();
      }
    }
    if (map.isNotEmpty) {
      await box.putAll(map);
    }
  }

  /// Updates or inserts a single group room in the cache.
  Future<void> saveGroupRoom(types.Room room, {String? userId}) async {
    final box = await _openGroupRoomsBox(userId);
    final targetUserId = ChatCacheBoxes.resolveUserId(userId);
    if (room.shouldHideForUser(targetUserId)) {
      await box.delete(room.id);
    } else {
      await box.put(room.id, room.toJson());
    }
  }

  /// Removes a group room from local cache.
  Future<void> deleteGroupRoomFromCache(String roomId, {String? userId}) async {
    final box = await _openGroupRoomsBox(userId);
    await box.delete(roomId);
    await clearRoomMessages(roomId);
  }

  /// Retrieves cached group session rooms for the user.
  Future<List<types.Room>> getCachedGroupRooms({String? userId}) async {
    final box = await _openGroupRoomsBox(userId);
    final targetUserId = ChatCacheBoxes.resolveUserId(userId);
    final List<types.Room> rooms = [];
    for (final value in box.values) {
      try {
        final castedMap = _deepCastMap(value);
        _sanitizeRoomMap(castedMap);
        final room = types.Room.fromJson(castedMap);
        if (!room.shouldHideForUser(targetUserId)) {
          rooms.add(room);
        }
      } catch (e) {
        print('❌ [getCachedGroupRooms Error]: $e');
      }
    }

    return rooms..sort((a, b) {
      if (a.isNotRead != b.isNotRead) {
        return a.isNotRead ? -1 : 1;
      }
      return (b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0);
    });
  }

  // --- Messages Cache Operations ---

  /// Caches a list of message maps for a specific room.
  Future<void> saveMessages(String roomId, List<Map<String, dynamic>> messageMaps) async {
    final box = await _openMessagesBox(roomId);
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
  Future<void> saveMessage(String roomId, Map<String, dynamic> messageMap) async {
    final box = await _openMessagesBox(roomId);
    final msgId = messageMap['id']?.toString();
    if (msgId != null) {
      await box.put(msgId, messageMap);
    }
  }

  /// Retrieves all cached messages for a specific room.
  Future<List<types.Message>> getCachedMessages(String roomId) async {
    final box = await _openMessagesBox(roomId);
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
          final isOldAttachment = (type == 'file' || type == 'video') && (nowTimeMillis - createdAt).abs() > 2592000000;

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

    return messages..sort((a, b) => (b.createdAt ?? 0).compareTo(a.createdAt ?? 0));
  }

  /// Clear messages box for a room.
  Future<void> clearRoomMessages(String roomId) async {
    final box = await _openMessagesBox(roomId);
    await box.clear();
  }

  // --- User Cache Operations ---

  /// Caches a user profile.
  Future<void> cacheUser(types.User user) async {
    final box = await _openUsersBox();
    await box.put(user.id, user.toJson());
  }

  /// Caches a list of users.
  Future<void> saveUsers(List<types.User> users) async {
    final box = await _openUsersBox();
    final map = <String, Map>{};
    for (final user in users) {
      if (user.id == '0') continue;
      map[user.id] = user.toJson();
    }
    if (map.isNotEmpty) {
      await box.putAll(map);
    }
  }

  /// Retrieves all cached users.
  Future<List<types.User>> getCachedUsers() async {
    final box = await _openUsersBox();
    final users = <types.User>[];
    for (final value in box.values) {
      try {
        final casted = _deepCastMap(value);
        users.add(types.User.fromJson(casted));
      } catch (_) {}
    }
    return users..sort((a, b) => (b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0));
  }

  /// Retrieves a cached user profile by ID.
  Future<types.User?> getCachedUser(String userId) async {
    final box = await _openUsersBox();
    final value = box.get(userId);
    if (value == null) return null;
    try {
      final castedMap = _deepCastMap(value);
      return types.User.fromJson(castedMap);
    } catch (e) {
      return null;
    }
  }

  /// Removes a user from local cache.
  Future<void> deleteUserFromCache(String userId) async {
    final box = await _openUsersBox();
    await box.delete(userId);
  }

  // --- Helper Methods ---

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

  void _sanitizeRoomMap(Map<String, dynamic> roomMap) {
    if (roomMap['metadata'] is! Map) {
      roomMap['metadata'] = <String, dynamic>{};
    }
    if (roomMap['users'] is! List) {
      if (roomMap['userIds'] is List) {
        roomMap['users'] = roomMap['userIds'];
      } else {
        roomMap['users'] = <dynamic>[];
      }
    }
    if (roomMap['users'] is List) {
      for (final u in (roomMap['users'] as List)) {
        if (u is Map) {
          final r = u['role']?.toString().toLowerCase();
          if (r != 'admin' && r != 'agent' && r != 'moderator' && r != 'user') {
            u['role'] = 'user';
          }
          // metadata must be Map or absent — never List
          if (u['metadata'] != null && u['metadata'] is! Map) {
            u.remove('metadata');
          }
        }
      }
    }
    if (roomMap['lastMessages'] is List) {
      for (final m in (roomMap['lastMessages'] as List)) {
        if (m is Map) {
          // sanitize message metadata
          if (m['metadata'] != null && m['metadata'] is! Map) {
            m.remove('metadata');
          }
          if (m['author'] is Map) {
            final author = m['author'] as Map;
            final r = author['role']?.toString().toLowerCase();
            if (r != 'admin' && r != 'agent' && r != 'moderator' && r != 'user') {
              author['role'] = 'user';
            }
            // author.metadata must be Map or absent
            if (author['metadata'] != null && author['metadata'] is! Map) {
              author.remove('metadata');
            }
          }
        }
      }
    }
  }
}

Map<String, Map> _parseUsersSeedJson(String jsonStr) {
  final list = jsonDecode(jsonStr) as List? ?? [];
  final map = <String, Map>{};
  for (final item in list) {
    if (item is Map && item['id'] != null && item['id'].toString() != '0') {
      map[item['id'].toString()] = item;
    }
  }
  return map;
}



class _RoomHydratePayload {
  final String jsonStr;
  final Map<String, Map> usersMap;

  _RoomHydratePayload({required this.jsonStr, required this.usersMap});
}

Map<String, Map> _parseAndHydrateRoomsJson(_RoomHydratePayload payload) {
  final list = jsonDecode(payload.jsonStr) as List? ?? [];
  final map = <String, Map>{};

  for (final item in list) {
    if (item is Map && item['id'] != null) {
      final roomMap = _deepCastMapStatic(item);
      if (roomMap['metadata'] is! Map) {
        roomMap['metadata'] = <String, dynamic>{};
      }
      final roomId = item['id'].toString();
      final rawUsers = roomMap['users'] ?? roomMap['userIds'] ?? [];
      var usersList = (rawUsers is List) ? List.from(rawUsers) : [];
      if (usersList.isEmpty && roomId.contains('_')) {
        usersList = roomId.split('_');
      }
      final hydratedUsers = <Map<String, dynamic>>[];
      for (final u in usersList) {
        if (u is Map) {
          final userMap = _deepCastMapStatic(u);
          if (userMap['metadata'] is! Map) userMap.remove('metadata');
          hydratedUsers.add(userMap);
        } else {
          final userId = u.toString();
          final cachedUser = payload.usersMap[userId];
          if (cachedUser != null) {
            final userMap = _deepCastMapStatic(cachedUser);
            if (userMap['metadata'] is! Map) userMap.remove('metadata');
            hydratedUsers.add(userMap);
          } else {
            hydratedUsers.add({'id': userId, 'firstName': 'User $userId', 'role': 'user'});
          }
        }
      }
      roomMap['users'] = hydratedUsers;
      map[item['id'].toString()] = roomMap;
    }
  }
  return map;
}

/// Top-level deep cast for use inside isolates (no instance access).
Map<String, dynamic> _deepCastMapStatic(Map map) {
  return map.map((key, value) {
    final stringKey = key.toString();
    if (value is Map) {
      return MapEntry(stringKey, _deepCastMapStatic(value));
    } else if (value is List) {
      return MapEntry(
        stringKey,
        value.map((item) {
          if (item is Map) return _deepCastMapStatic(item);
          return item;
        }).toList(),
      );
    } else {
      return MapEntry(stringKey, value);
    }
  });
}

