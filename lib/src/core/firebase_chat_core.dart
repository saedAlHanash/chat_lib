import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';

import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import '../../chat_lib.dart';
import '../config/chat_config.dart';
import '../cache/chat_cache_manager.dart';

part 'firebase_chat_users.dart';
part 'firebase_chat_rooms.dart';
part 'firebase_chat_group_rooms.dart';
part 'firebase_chat_common_rooms.dart';
part 'firebase_chat_messages.dart';
part 'firebase_chat_helpers.dart';

/// Role enum extension helper
extension _RoleToString on types.Role {
  String toShortString() => toString().split('.').last;
}

/// RoomType enum extension helper
extension _RoomTypeToString on types.RoomType {
  String toShortString() => toString().split('.').last;
}

/// The core class that interacts with Firebase Firestore and manages caching.
class FirebaseChatCore {
  FirebaseChatCore._privateConstructor();

  static final FirebaseChatCore instance = FirebaseChatCore._privateConstructor();

  late ChatConfig _config;
  bool _isInitialized = false;

  /// Initializes the FirebaseChatCore service with configuration.
  void initialize(ChatConfig config) {
    _config = config;
    _isInitialized = true;
    ChatCacheManager.instance.init(
      version: config.cacheVersion,
      directRoomsSeedAssetPath: config.directRoomsSeedAssetPath,
      groupRoomsSeedAssetPath: config.groupRoomsSeedAssetPath,
      usersSeedAssetPath: config.usersSeedAssetPath,
    );
  }

  /// Getters for configurations
  ChatConfig get config => _config;

  String get currentUserId {
    _checkInitialized();
    return _config.currentUserId();
  }

  FirebaseFirestore get _firestore {
    _checkInitialized();
    return _config.firestore;
  }

  void _checkInitialized() {
    if (!_isInitialized) {
      throw StateError('FirebaseChatCore has not been initialized. Call initialize() first.');
    }
  }

  /// Uploads a file using the configured [uploadDelegate].
  Future<String> uploadFile(String filePath, {String? mimeType, Map<String, dynamic>? customArgs}) async {
    _checkInitialized();
    if (_config.uploadDelegate == null) {
      throw StateError('uploadDelegate is not configured.');
    }
    return await _config.uploadDelegate!(filePath, mimeType: mimeType, customArgs: customArgs);
  }

  /// Exports all cached direct rooms, group rooms, and users as individual JSON files into a directory.
  Future<Map<String, String>> exportAllSeedFiles(
    String directoryPath, {
    String directRoomsKey = 'all_rooms',
    String groupRoomsKey = 'all_group_rooms',
    bool pretty = true,
  }) =>
      ChatCacheManager.instance.exportAllSeedFiles(
        directoryPath,
        directRoomsKey: directRoomsKey,
        groupRoomsKey: groupRoomsKey,
        pretty: pretty,
      );

  /// Seeds direct rooms from asset if the direct rooms box is empty.
  Future<void> seedDirectRoomsFromAsset(String assetPath, {String userId = 'all_rooms'}) =>
      ChatCacheManager.instance.seedDirectRoomsFromAsset(assetPath, userId: userId);

  /// Seeds group rooms from asset if the group rooms box is empty.
  Future<void> seedGroupRoomsFromAsset(String assetPath, {String userId = 'all_group_rooms'}) =>
      ChatCacheManager.instance.seedGroupRoomsFromAsset(assetPath, userId: userId);

  /// Seeds users from asset if the users box is empty.
  Future<void> seedUsersFromAsset(String assetPath) =>
      ChatCacheManager.instance.seedUsersFromAsset(assetPath);
}
