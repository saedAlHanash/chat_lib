import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import '../../chat_lib.dart';
import '../config/chat_config.dart';
import '../cache/chat_cache_manager.dart';

part 'firebase_chat_users.dart';
part 'firebase_chat_rooms.dart';
part 'firebase_chat_group_rooms.dart';
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
}
