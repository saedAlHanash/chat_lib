import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import '../../chat_lib.dart';
import '../config/chat_config.dart';
import '../cache/chat_cache_manager.dart';

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

  // --- Users Operations ---

  /// Creates a User in Firestore.
  Future<void> createUserInFirestore(types.User user) async {
    if (user.id == '0') return;

    final data = {
      'createdAt': FieldValue.serverTimestamp(),
      'fitness_id': user.id,
      'firstName': user.firstName,
      'imageUrl': user.imageUrl,
      'lastName': user.lastName,
      'lastSeen': FieldValue.serverTimestamp(),
      'role': user.role?.toShortString() ?? types.Role.user.toShortString(),
      'updatedAt': FieldValue.serverTimestamp(),
      'userAppId': currentUserId,
      'metadata': user.metadata,
    };

    await _firestore.collection(_config.usersCollection).doc(user.id).set(data);
    await ChatCacheManager.instance.cacheUser(user);
  }

  /// Creates multiple Users in Firestore using a batch write.
  Future<void> createUsersInFirestore(List<types.User> users) async {
    final batch = _firestore.batch();
    for (final user in users) {
      if (user.id == '0') continue;
      final data = {
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'fitness_id': user.id,
        'firstName': user.firstName,
        'imageUrl': user.imageUrl,
        'lastName': user.lastName,
        'lastSeen': FieldValue.serverTimestamp(),
        'role': user.role?.toShortString() ?? types.Role.user.toShortString(),
        'userAppId': currentUserId,
        'metadata': user.metadata,
      };
      final docRef = _firestore.collection(_config.usersCollection).doc(user.id);
      batch.set(docRef, data, SetOptions(merge: true));
      await ChatCacheManager.instance.cacheUser(user);
    }
    await batch.commit();
  }

  /// Updates a user profile in Firestore.
  Future<void> updateUser(types.User user) async {
    if (user.id == '0') return;

    final data = {
      'fitness_id': user.id,
      'firstName': user.firstName,
      'imageUrl': user.imageUrl,
      'lastName': user.lastName,
      'metadata': user.metadata,
      'lastSeen': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'userAppId': currentUserId,
    };

    await _firestore.collection(_config.usersCollection).doc(user.id).update(data);
    await ChatCacheManager.instance.cacheUser(user);
  }

  /// Query for users in Firestore.
  Query<Map<String, dynamic>> usersQuery(Timestamp updateTime) {
    return _firestore
        .collection(_config.usersCollection)
        .orderBy('updatedAt', descending: true)
        .where('updatedAt', isGreaterThan: updateTime);
  }

  /// Deletes a user document from Firestore users collection.
  Future<void> deleteUser(String id) async {
    await _firestore.collection(_config.usersCollection).doc(id).delete();
  }

  /// Helper to create a user with email.
  Future<bool> createMe(String id, String name, String email) async {
    try {
      await createUserInFirestore(
        types.User(id: id, firstName: name, imageUrl: '', lastName: '', role: types.Role.user, metadata: {'email': email}),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Retrieves a user profile from Firestore by ID.
  Future<types.User?> getUserFromFirestore(String userId) async {
    final doc = await _firestore.collection(_config.usersCollection).doc(userId).get();
    final data = doc.data();
    if (data == null) return null;

    data['createdAt'] = data['createdAt'] is Timestamp
        ? (data['createdAt'] as Timestamp).millisecondsSinceEpoch
        : (data['createdAt'] ?? 0);
    data['id'] = doc.id;
    data['lastSeen'] = data['lastSeen'] is Timestamp
        ? (data['lastSeen'] as Timestamp).millisecondsSinceEpoch
        : (data['lastSeen'] ?? 0);
    data['role'] = data['role'] ?? types.Role.user.name;
    data['updatedAt'] = data['updatedAt'] is Timestamp
        ? (data['updatedAt'] as Timestamp).millisecondsSinceEpoch
        : (data['updatedAt'] ?? 0);

    return types.User.fromJson(data);
  }

  /// Resolves user with local cache first (Read-Through Cache).
  Future<types.User> fetchUser(String userId) async {
    final cached = await ChatCacheManager.instance.getCachedUser(userId);
    if (cached != null) return cached;

    try {
      final user = await getUserFromFirestore(userId);
      if (user != null) {
        await ChatCacheManager.instance.cacheUser(user);
        return user;
      }
    } catch (_) {}

    return types.User(id: userId, firstName: 'User $userId');
  }

  // --- Rooms Operations ---

  /// Query for rooms belonging to the current user.
  Query<Map<String, dynamic>> roomsQuery(Timestamp? updateTime) {
    return _firestore
        .collection(_config.roomsCollection)
        .orderBy('updatedAt', descending: true)
        .where('userIds', arrayContains: currentUserId)
        .where('updatedAt', isGreaterThan: updateTime ?? Timestamp.fromMillisecondsSinceEpoch(0));
  }

  /// Retrieves a direct room by other user's ID.
  Future<types.Room?> getRoomByUserId(String otherUserId) async {
    final userIds = [currentUserId, otherUserId]..sort();

    final result = await _firestore
        .collection(_config.roomsCollection)
        .orderBy('updatedAt', descending: true)
        .where('userIds', isEqualTo: userIds)
        .limit(1)
        .get();

    final rooms = await _processRoomsQuery(result);
    return rooms.firstOrNull;
  }

  /// Creates a direct chatroom with another user.
  Future<types.Room> createRoom(String otherUserId) async {
    final existingRoom = await getRoomByUserId(otherUserId);
    if (existingRoom != null) return existingRoom;

    final userIds = [currentUserId, otherUserId]..sort();

    final docRef = await _firestore.collection(_config.roomsCollection).add({
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'type': types.RoomType.direct.toShortString(),
      'userIds': userIds,
      'metadata': {},
      'imageUrl': null,
      'name': null,
      'userRoles': null,
    });

    final docSnap = await docRef.get();
    final room = await _processRoomDocument(docSnap);
    await ChatCacheManager.instance.saveRoom(currentUserId, room);
    return room;
  }

  /// Creates a group chatroom with a name, optional image, users, and sets creator as admin.
  Future<types.Room> createGroupRoom({
    required String name,
    String? id,
    String? imageUrl,
    List<types.User> users = const [],
    RoomCategory category = RoomCategory.group,
    Map<String, dynamic>? metadata,
  }) async {
    final userIds = {currentUserId, ...users.map((u) => u.id)}.toList();

    final initialMetadata = <String, dynamic>{...?metadata, 'adminId': currentUserId, 'category': category.toShortString()};

    final collectionName = (category == RoomCategory.groupSession)
        ? _config.groupSessionRoomsCollection
        : _config.roomsCollection;

    final docRef = id != null ? _firestore.collection(collectionName).doc(id) : _firestore.collection(collectionName).doc();
    final batch = _firestore.batch();

    batch.set(docRef, {
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'type': types.RoomType.group.toShortString(),
      'userIds': userIds,
      'name': name,
      'imageUrl': imageUrl,
      'metadata': initialMetadata,
    });

    for (final userId in userIds) {
      final role = (userId == currentUserId) ? types.Role.admin : types.Role.user;
      final memberRef = docRef.collection('members').doc(userId);
      batch.set(memberRef, {
        'userId': userId,
        'role': role.toShortString(),
        'canSendMessages': true,
        'canSendMedia': true,
        'isBanned': false,
        'joinedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    final docSnap = await docRef.get();
    final room = await _processRoomDocument(docSnap);
    await ChatCacheManager.instance.saveRoom(currentUserId, room);
    return room;
  }

  /// Adds users to an existing group room.
  Future<void> addUsersToGroup(String roomId, List<types.User> newUsers) async {
    final collectionName = _getCollectionForRoom(roomId);
    final docRef = _firestore.collection(collectionName).doc(roomId);

    final batch = _firestore.batch();

    batch.update(docRef, {
      'userIds': FieldValue.arrayUnion(newUsers.map((u) => u.id).toList()),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    for (final u in newUsers) {
      final memberRef = docRef.collection('members').doc(u.id);
      batch.set(memberRef, {
        'userId': u.id,
        'role': types.Role.user.toShortString(),
        'canSendMessages': true,
        'canSendMedia': true,
        'isBanned': false,
        'joinedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  /// Removes a user from a group room.
  Future<void> removeUserFromGroup(String roomId, String userId) async {
    final collectionName = _getCollectionForRoom(roomId);
    final docRef = _firestore.collection(collectionName).doc(roomId);

    final batch = _firestore.batch();

    batch.update(docRef, {
      'userIds': FieldValue.arrayRemove([userId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final memberRef = docRef.collection('members').doc(userId);
    batch.delete(memberRef);

    await batch.commit();
  }

  /// Adds users by their String IDs to an existing group room.
  Future<void> addUsersToGroupByIds(String roomId, List<String> newUserIds) async {
    final collectionName = _getCollectionForRoom(roomId);
    final docRef = _firestore.collection(collectionName).doc(roomId);

    final batch = _firestore.batch();

    batch.update(docRef, {'userIds': FieldValue.arrayUnion(newUserIds), 'updatedAt': FieldValue.serverTimestamp()});

    for (final id in newUserIds) {
      final memberRef = docRef.collection('members').doc(id);
      batch.set(memberRef, {
        'userId': id,
        'role': types.Role.user.toShortString(),
        'canSendMessages': true,
        'canSendMedia': true,
        'isBanned': false,
        'joinedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  /// Leaves a group room for the current user.
  Future<void> leaveGroup(String roomId) async {
    await removeUserFromGroup(roomId, currentUserId);
  }

  /// Updates user role in a group room (e.g. promote to admin or demote to user).
  Future<void> updateUserGroupRole(String roomId, String userId, types.Role role) async {
    final collectionName = _getCollectionForRoom(roomId);
    final docRef = _firestore.collection(collectionName).doc(roomId);
    final memberRef = docRef.collection('members').doc(userId);

    final batch = _firestore.batch();

    batch.update(memberRef, {'role': role.toShortString()});

    batch.update(docRef, {'updatedAt': FieldValue.serverTimestamp()});

    await batch.commit();
  }

  /// Updates user group permissions (canSendMessages, canSendMedia, isBanned).
  Future<void> updateUserGroupPermissions(
    String roomId,
    String userId, {
    bool? canSendMessages,
    bool? canSendMedia,
    bool? isBanned,
  }) async {
    final collectionName = _getCollectionForRoom(roomId);
    final docRef = _firestore.collection(collectionName).doc(roomId);
    final memberRef = docRef.collection('members').doc(userId);

    final updates = <String, dynamic>{};
    if (canSendMessages != null) updates['canSendMessages'] = canSendMessages;
    if (canSendMedia != null) updates['canSendMedia'] = canSendMedia;
    if (isBanned != null) updates['isBanned'] = isBanned;

    if (updates.isNotEmpty) {
      final batch = _firestore.batch();
      batch.update(memberRef, updates);
      batch.update(docRef, {'updatedAt': FieldValue.serverTimestamp()});
      await batch.commit();
    }
  }

  /// Bans a user from a group room (sets isBanned = true).
  Future<void> banUserFromGroup(String roomId, String userId) async {
    await updateUserGroupPermissions(roomId, userId, isBanned: true, canSendMessages: false, canSendMedia: false);
  }

  /// Unbans a user from a group room (sets isBanned = false).
  Future<void> unbanUserFromGroup(String roomId, String userId) async {
    await updateUserGroupPermissions(roomId, userId, isBanned: false, canSendMessages: true, canSendMedia: true);
  }

  /// Updates the latest seen timestamp for the current user in a room.
  Future<void> latestSeenRoom(types.Room room) async {
    await _firestore.collection(_config.roomsCollection).doc(room.id).update({
      'latestSeen$currentUserId': FieldValue.serverTimestamp(),
      'isOnline$currentUserId': false,
    });

    // Update local metadata
    final metadata = Map<String, dynamic>.from(room.metadata ?? {});
    metadata['latestSeen'] = room.updatedAt;
    metadata['latestSeen$currentUserId'] = room.updatedAt;

    final updatedRoom = room.copyWith(metadata: metadata);
    await ChatCacheManager.instance.saveRoom(currentUserId, updatedRoom);
  }

  /// Sets the current user's online state in a room.
  Future<void> setMyState(types.Room room, bool isOnline) async {
    await _firestore.collection(_config.roomsCollection).doc(room.id).update({'isOnline$currentUserId': isOnline});
  }

  // --- Messages Operations ---

  String _getCollectionForRoom(String roomId, {RoomCategory? category}) {
    if (category == RoomCategory.groupSession || roomId.startsWith('group_bundle_') || RegExp(r'^\d+$').hasMatch(roomId)) {
      return _config.groupSessionRoomsCollection;
    }
    return _config.roomsCollection;
  }

  /// Query for messages in a room.
  Query<Map<String, dynamic>> messagesQuery(Timestamp? updateTime, String roomId) {
    final collection = _getCollectionForRoom(roomId);
    return _firestore
        .collection('$collection/$roomId/messages')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .where('updatedAt', isGreaterThan: updateTime ?? Timestamp.fromMillisecondsSinceEpoch(0));
  }

  /// Deletes a message (soft delete).
  Future<void> deleteMessage(String messageId, String roomId) async {
    final collection = _getCollectionForRoom(roomId);
    await _firestore.collection('$collection/$roomId/messages').doc(messageId).update({
      'updatedAt': FieldValue.serverTimestamp(),
      'metadata': {'isDeleted': true},
    });
  }

  /// Sends a message, supports delegate file upload if needed.
  Future<void> sendMessage(dynamic partialMessage, String roomId, {String? senderId}) async {
    final finalSenderId = senderId ?? currentUserId;
    final collection = _getCollectionForRoom(roomId);

    // Check group permissions if group room
    final memberDoc = await _firestore.collection('$collection/$roomId/members').doc(finalSenderId).get();
    if (memberDoc.exists) {
      final perms = memberDoc.data() ?? {};
      if (perms['isBanned'] == true) {
        throw StateError('User is banned from this group.');
      }
      if (perms['canSendMessages'] == false) {
        throw StateError('User is restricted from sending messages in this group.');
      }
      final isMedia =
          partialMessage is types.PartialFile ||
          partialMessage is types.PartialImage ||
          partialMessage is types.PartialAudio;
      if (isMedia && perms['canSendMedia'] == false) {
        throw StateError('User is restricted from sending media in this group.');
      }
    } else {
      final roomDoc = await _firestore.collection(collection).doc(roomId).get();
      if (roomDoc.exists) {
        final roomData = roomDoc.data() ?? {};
        if (roomData['type'] == types.RoomType.group.toShortString()) {
          final metadata = roomData['metadata'] as Map<String, dynamic>? ?? {};
          final userPermissions = metadata['userPermissions'] as Map<String, dynamic>? ?? {};
          final perms = userPermissions[finalSenderId] as Map<String, dynamic>?;

          if (perms != null) {
            if (perms['isBanned'] == true) {
              throw StateError('User is banned from this group.');
            }
            if (perms['canSendMessages'] == false) {
              throw StateError('User is restricted from sending messages in this group.');
            }
            final isMedia =
                partialMessage is types.PartialFile ||
                partialMessage is types.PartialImage ||
                partialMessage is types.PartialAudio;
            if (isMedia && perms['canSendMedia'] == false) {
              throw StateError('User is restricted from sending media in this group.');
            }
          }
        }
      }
    }

    types.Message? message;

    // Handle File Upload delegation if needed
    if (partialMessage is types.PartialFile) {
      var uri = partialMessage.uri;
      if (!uri.startsWith('http') && _config.uploadDelegate != null) {
        uri = await _config.uploadDelegate!(uri, mimeType: partialMessage.mimeType);
      }
      message = types.FileMessage.fromPartial(
        author: types.User(id: finalSenderId),
        id: '',
        partialFile: types.PartialFile(
          mimeType: partialMessage.mimeType,
          name: partialMessage.name,
          size: partialMessage.size,
          uri: uri,
        ),
      );
    } else if (partialMessage is types.PartialImage) {
      var uri = partialMessage.uri;
      if (!uri.startsWith('http') && _config.uploadDelegate != null) {
        uri = await _config.uploadDelegate!(uri);
      }
      message = types.ImageMessage.fromPartial(
        author: types.User(id: finalSenderId),
        id: '',
        partialImage: types.PartialImage(
          height: partialMessage.height,
          name: partialMessage.name,
          size: partialMessage.size,
          uri: uri,
          width: partialMessage.width,
        ),
      );
    } else if (partialMessage is types.PartialAudio) {
      var uri = partialMessage.uri;
      if (!uri.startsWith('http') && _config.uploadDelegate != null) {
        uri = await _config.uploadDelegate!(uri);
      }
      message = types.AudioMessage.fromPartial(
        author: types.User(id: finalSenderId),
        id: '',
        partialAudio: types.PartialAudio(
          duration: partialMessage.duration,
          name: partialMessage.name,
          size: partialMessage.size,
          uri: uri,
        ),
      );
    } else if (partialMessage is types.PartialCustom) {
      message = types.CustomMessage.fromPartial(
        author: types.User(id: finalSenderId),
        id: '',
        partialCustom: partialMessage,
      );
    } else if (partialMessage is types.PartialText) {
      message = types.TextMessage.fromPartial(
        author: types.User(id: finalSenderId),
        id: '',
        partialText: partialMessage,
      );
    }

    if (message != null) {
      final messageMap = message.toJson();
      messageMap.removeWhere((key, value) => key == 'author' || key == 'id');
      messageMap['authorId'] = finalSenderId;
      messageMap['createdAt'] = FieldValue.serverTimestamp();
      messageMap['updatedAt'] = FieldValue.serverTimestamp();

      await _firestore.collection('$collection/$roomId/messages').add(messageMap);

      await _firestore.collection(collection).doc(roomId).update({
        'updatedAt': FieldValue.serverTimestamp(),
        'latestMessage': messageMap,
      });
    }
  }

  // --- Real-time Streams with Caching ---

  /// Emits a stream of rooms for the current user, synchronized with Firestore and cached locally.
  Future<Stream<List<types.Room>>> getRoomsStream({Timestamp? updateTime}) async {
    final controller = StreamController<List<types.Room>>.broadcast();

    // 1. Emit cached rooms immediately
    final listFromCache = await ChatCacheManager.instance.getCachedRooms(currentUserId, .direct);
    if (!controller.isClosed && listFromCache.isNotEmpty) {
      controller.add(listFromCache);
    }

    final updateTime = Timestamp.fromMillisecondsSinceEpoch(listFromCache.firstOrNull?.updatedAt ?? 0);

    // 2. Query Firestore and update cache + emit
    StreamSubscription? subscription;
    try {
      subscription = roomsQuery(updateTime).snapshots().listen(
        (snapshot) async {
          try {
            final rooms = await _processRoomsQuery(snapshot);
            if (rooms.isNotEmpty) {
              await ChatCacheManager.instance.saveRooms(currentUserId, rooms);
              final updatedCached = await ChatCacheManager.instance.getCachedRooms(currentUserId, .direct);
              if (!controller.isClosed) controller.add(updatedCached);
            }
          } catch (e, st) {
            print('❌ [FirebaseChatCore _processRoomsQuery Error]: $e');
            print(st);
            if (!controller.isClosed) controller.addError(e);
          }
        },
        onError: (err) {
          print('❌ [FirebaseChatCore roomsQuery onError]: $err');
          if (!controller.isClosed) controller.addError(err);
        },
      );
    } catch (e) {
      print('❌ [FirebaseChatCore getRoomsStream catch]: $e');
      controller.addError(e);
    }

    controller.onCancel = () {
      subscription?.cancel();
    };

    return controller.stream;
  }

  /// Direct one-time fetch of rooms for the current user from Firestore.
  Future<List<types.Room>> getRooms() async {
    try {
      print('🔍 [getRooms] Querying Firestore for userIds arrayContains "$currentUserId"...');

      final querySnapshot = await _firestore
          .collection(_config.roomsCollection)
          .where('userIds', arrayContains: currentUserId)
          .get();

      print('🔍 [getRooms] Found ${querySnapshot.docs.length} raw room document(s) in Firestore.');

      final rooms = await _processRoomsQuery(querySnapshot);
      print('🔍 [getRooms] Processed ${rooms.length} room object(s).');

      if (rooms.isNotEmpty) {
        await ChatCacheManager.instance.saveRooms(currentUserId, rooms);
      }
      return rooms;
    } catch (e, st) {
      print('❌ [FirebaseChatCore getRooms Error]: $e');
      print(st);
      rethrow;
    }
  }

  // --- Group Session Rooms (Collection: Configurable via ChatConfig) ---

  /// Query for group session rooms belonging to the current user.
  Query<Map<String, dynamic>> groupSessionRoomsQuery(Timestamp? updateTime) {
    return _firestore
        .collection(_config.groupSessionRoomsCollection)
        .orderBy('updatedAt', descending: true)
        .where('userIds', arrayContains: currentUserId)
        .where('updatedAt', isGreaterThan: updateTime ?? Timestamp.fromMillisecondsSinceEpoch(0));
  }

  /// Emits a stream of group session rooms for current user from configured group session collection.
  Future<Stream<List<types.Room>>> getGroupSessionRoomsStream() async {
    final controller = StreamController<List<types.Room>>.broadcast();

    // 1. Emit cached rooms immediately
    final listFromCache = await ChatCacheManager.instance.getCachedRooms(currentUserId, .group);
    if (!controller.isClosed && listFromCache.isNotEmpty) {
      controller.add(listFromCache);
    }

    final updateTime = Timestamp.fromMillisecondsSinceEpoch(listFromCache.firstOrNull?.updatedAt ?? 0);

    // 2. Query Firestore and update cache + emit
    StreamSubscription? subscription;

    try {
      subscription = groupSessionRoomsQuery(updateTime).snapshots().listen(
        (snapshot) async {
          try {
            final rooms = await _processRoomsQuery(snapshot);
            if (rooms.isNotEmpty) {
              await ChatCacheManager.instance.saveRooms(currentUserId, rooms);
              final updatedCached = await ChatCacheManager.instance.getCachedRooms(currentUserId, .group);
              final groupRooms = updatedCached.where((r) => r.type == types.RoomType.group).toList();
              if (!controller.isClosed) controller.add(groupRooms);
            }
          } catch (e, st) {
            print('❌ [FirebaseChatCore getGroupSessionRoomsStream process Error]: $e');
            print(st);
            if (!controller.isClosed) controller.addError(e);
          }
        },
        onError: (err) {
          print('❌ [FirebaseChatCore getGroupSessionRoomsStream onError]: $err');
          if (!controller.isClosed) controller.addError(err);
        },
      );
    } catch (e) {
      print('❌ [FirebaseChatCore getGroupSessionRoomsStream catch]: $e');
      controller.addError(e);
    }

    controller.onCancel = () {
      subscription?.cancel();
    };

    return controller.stream;
  }

  /// Direct one-time fetch of group session rooms for current user.
  Future<List<types.Room>> getGroupSessionRooms() async {
    try {
      final querySnapshot = await _firestore
          .collection(_config.groupSessionRoomsCollection)
          .where('userIds', arrayContains: currentUserId)
          .get();

      final rooms = await _processRoomsQuery(querySnapshot);
      if (rooms.isNotEmpty) {
        await ChatCacheManager.instance.saveRooms(currentUserId, rooms);
      }
      return rooms;
    } catch (e, st) {
      print('❌ [FirebaseChatCore getGroupSessionRooms Error]: $e');
      print(st);
      return [];
    }
  }

  /// Mute/Unmute a member in a Group Session Room (Admin action).
  Future<void> muteMemberInGroupSession(String roomId, String userId, bool isMuted) async {
    await updateUserGroupPermissions(roomId, userId, isBanned: isMuted, canSendMessages: !isMuted, canSendMedia: !isMuted);
  }

  /// Remove/Kick a member from a Group Session Room (Admin action).
  Future<void> removeMemberFromGroupSession(String roomId, String userId) async {
    await removeUserFromGroup(roomId, userId);
  }

  /// Emits a stream of messages in a room, synchronized with Firestore and cached locally.
  Stream<List<types.Message>> getMessagesStream({required String roomId, Timestamp? updateTime}) {
    final controller = StreamController<List<types.Message>>.broadcast();

    // 1. Emit cached messages immediately
    ChatCacheManager.instance.getCachedMessages(roomId, currentUserId).then((cached) {
      if (!controller.isClosed && cached.isNotEmpty) {
        // Sort newest first
        cached.sort((a, b) => (b.createdAt ?? 0).compareTo(a.createdAt ?? 0));
        controller.add(cached);
      }
    });

    // 2. Query Firestore and update cache + emit
    StreamSubscription? subscription;
    try {
      subscription = messagesQuery(updateTime, roomId).snapshots().listen(
        (snapshot) async {
          final messagesList = <Map<String, dynamic>>[];
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final authorId = data['authorId'] as String?;
            if (authorId != null) {
              final author = await fetchUser(authorId);
              data['author'] = author.toJson();
              data['createdAt'] = data['createdAt'] is Timestamp
                  ? (data['createdAt'] as Timestamp).millisecondsSinceEpoch
                  : (data['createdAt'] ?? 0);
              data['id'] = doc.id;
              data['updatedAt'] = data['updatedAt'] is Timestamp
                  ? (data['updatedAt'] as Timestamp).millisecondsSinceEpoch
                  : (data['updatedAt'] ?? 0);
              messagesList.add(data);
            }
          }

          if (messagesList.isNotEmpty) {
            await ChatCacheManager.instance.saveMessages(roomId, currentUserId, messagesList);
            final updatedCached = await ChatCacheManager.instance.getCachedMessages(roomId, currentUserId);
            // Sort newest first
            updatedCached.sort((a, b) => (b.createdAt ?? 0).compareTo(a.createdAt ?? 0));
            if (!controller.isClosed) {
              controller.add(updatedCached);
            }
          }
        },
        onError: (err) {
          if (!controller.isClosed) controller.addError(err);
        },
      );
    } catch (e) {
      controller.addError(e);
    }

    controller.onCancel = () {
      subscription?.cancel();
    };

    return controller.stream;
  }

  // --- Helpers ---

  Future<List<types.Room>> _processRoomsQuery(QuerySnapshot<Map<String, dynamic>> query) async {
    final futures = query.docs.map((doc) => _processRoomDocument(doc));
    return await Future.wait(futures);
  }

  Future<types.Room> _processRoomDocument(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data()!;
    data['id'] = doc.id;
    data['createdAt'] = data['createdAt'] is Timestamp
        ? (data['createdAt'] as Timestamp).millisecondsSinceEpoch
        : (data['createdAt'] ?? 0);
    data['updatedAt'] = data['updatedAt'] is Timestamp
        ? (data['updatedAt'] as Timestamp).millisecondsSinceEpoch
        : (data['updatedAt'] ?? 0);

    var imageUrl = data['imageUrl'] as String?;
    var name = data['name'] as String?;
    final type = data['type'] as String;
    final userIds = data['userIds'] as List<dynamic>;

    final users = await Future.wait(userIds.map((userId) => fetchUser(userId as String)));
    final otherUserId = userIds.firstWhereOrNull((uId) => uId.toString() != currentUserId)?.toString();
    final otherUser = users.firstWhereOrNull((u) => u.id != currentUserId);

    if (type == types.RoomType.direct.toShortString() && otherUser != null) {
      imageUrl = otherUser.imageUrl;
      name = '${otherUser.firstName} ${otherUser.lastName ?? ''}'.trim();
    }

    data['imageUrl'] = imageUrl;
    data['name'] = name;
    data['users'] = users.map((u) => u.toJson()).toList();

    if (data['latestMessage'] != null && data['latestMessage'] is Map) {
      final message = Map<String, dynamic>.from(data['latestMessage'] as Map);
      final authorId = message['authorId'] as String?;
      if (authorId != null) {
        final author = await fetchUser(authorId);
        message['author'] = author.toJson();
      }
      message['createdAt'] = message['createdAt'] is Timestamp
          ? (message['createdAt'] as Timestamp).millisecondsSinceEpoch
          : (message['createdAt'] ?? 0);
      message['id'] = doc.id; // Map room doc ID as temp message ID
      message['updatedAt'] = message['updatedAt'] is Timestamp
          ? (message['updatedAt'] as Timestamp).millisecondsSinceEpoch
          : (message['updatedAt'] ?? 0);
      data['lastMessages'] = [message];
    }

    // Set latest seen metadata
    final Map<String, dynamic> metadata = Map<String, dynamic>.from(data['metadata'] ?? {});

    // Fetch members sub-collection and populate userRoles and userPermissions
    final collectionName = _getCollectionForRoom(doc.id);
    final membersSnap = await _firestore.collection(collectionName).doc(doc.id).collection('members').get();

    final userRoles = <String, String>{};
    final userPermissions = <String, Map<String, dynamic>>{};

    if (membersSnap.docs.isNotEmpty) {
      for (final memberDoc in membersSnap.docs) {
        final mData = memberDoc.data();
        final mUserId = memberDoc.id;
        final mRole = mData['role'] as String? ?? 'user';
        userRoles[mUserId] = mRole;
        userPermissions[mUserId] = {
          'canSendMessages': mData['canSendMessages'] ?? true,
          'canSendMedia': mData['canSendMedia'] ?? true,
          'isBanned': mData['isBanned'] ?? false,
        };
      }
    } else {
      // Fallback to legacy fields if sub-collection is empty
      if (data['userRoles'] != null) {
        userRoles.addAll(Map<String, String>.from(data['userRoles'] as Map));
      }
      if (metadata['userPermissions'] != null) {
        userPermissions.addAll(
          Map<String, Map<String, dynamic>>.from(
            (metadata['userPermissions'] as Map).map((k, v) => MapEntry(k as String, Map<String, dynamic>.from(v as Map))),
          ),
        );
      }
    }

    data['userRoles'] = userRoles;
    metadata['userRoles'] = userRoles;
    metadata['userPermissions'] = userPermissions;

    final latestSeenVal = data['latestSeen$currentUserId'];
    metadata['latestSeen'] = latestSeenVal is Timestamp ? latestSeenVal.millisecondsSinceEpoch : (latestSeenVal ?? 0);
    metadata['latestSeen$currentUserId'] = metadata['latestSeen'];

    // Set online status metadata
    if (otherUserId != null && otherUserId.trim().isNotEmpty) {
      final isOnlineVal = data['isOnline$otherUserId'];
      if (isOnlineVal != null) {
        if (isOnlineVal is bool) {
          metadata['isOnline'] = isOnlineVal;
        } else {
          metadata['isOnline'] = isOnlineVal.toString().toLowerCase() == 'true';
        }
      } else {
        metadata['isOnline'] = false;
      }
    }

    data['metadata'] = metadata;

    return types.Room.fromJson(data);
  }

  /// Clears token/metadata for current user and cleans up Hive local cache.
  Future<void> logout() async {
    final userId = currentUserId;
    try {
      await _firestore.collection(_config.usersCollection).doc(userId).update({
        'metadata': {},
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
    // await ChatCacheManager.instance.clearUserCache(userId);
  }

  /// Adds error log directly to errors collection in Firestore.
  void addError(String? error) {
    _firestore.collection('errors').add({
      'error': error,
      'userId': currentUserId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Logs events to logEvents collection.
  Future<void> logEvent(String type, {String? userName}) async {
    await _firestore.collection('${_config.isTestMode ? 'test_' : ''}logEvents').add({
      'createdAt': FieldValue.serverTimestamp(),
      'logType': type,
      'userIds': currentUserId,
      'name': userName,
    });
  }

  /// Gets the list of sent welcome message IDs.
  Future<List<int>> getSentWelcomeMessagesIds() async {
    try {
      final doc = await _firestore
          .collection('${_config.isTestMode ? 'test_' : ''}sentMessagesIds')
          .doc(currentUserId)
          .get();
      final data = doc.data();
      return List<int>.from(data?['ids'] ?? []);
    } catch (_) {
      return [];
    }
  }

  /// Sets the list of sent welcome message IDs.
  Future<void> addSentWelcomeMessagesId(List<int> ids) async {
    await _firestore.collection('${_config.isTestMode ? 'test_' : ''}sentMessagesIds').doc(currentUserId).set({'ids': ids});
  }
}
