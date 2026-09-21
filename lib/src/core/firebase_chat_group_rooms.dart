part of 'firebase_chat_core.dart';

/// Group session rooms operations extension on [FirebaseChatCore].
extension FirebaseChatGroupRooms on FirebaseChatCore {
  /// Creates a group chatroom with a name, optional image, users, and sets creator as admin.
  Future<types.Room> createGroupRoom({
    required String name,
    String? id,
    String? imageUrl,
    List<types.User> users = const [],
    Map<String, dynamic>? metadata,
  }) async {
    final userIds = {currentUserId, ...users.map((u) => u.id)}.toList();

    final initialMetadata = <String, dynamic>{...?metadata, 'adminId': currentUserId};

    final collectionName = _config.groupSessionRoomsCollection;

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
    await ChatCacheManager.instance.saveGroupRoom(room);
    return room;
  }

  /// Adds users to an existing group room.
  Future<void> addUsersToGroup(String roomId, List<types.User> newUsers) async {
    final collectionName = _config.groupSessionRoomsCollection;
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
    final collectionName = _config.groupSessionRoomsCollection;
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
    final collectionName = _config.groupSessionRoomsCollection;
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
    final collectionName = _config.groupSessionRoomsCollection;
    final docRef = _firestore.collection(collectionName).doc(roomId);
    final memberRef = docRef.collection('members').doc(userId);

    final batch = _firestore.batch();

    batch.update(memberRef, {'role': role.toShortString()});

    batch.update(docRef, {'updatedAt': FieldValue.serverTimestamp()});

    await batch.commit();
  }

  /// Updates user group permissions (canSendMessages, canSendMedia, isBanned) directly in members subcollection.
  Future<void> updateUserGroupPermissions(
    String roomId,
    String userId, {
    bool? canSendMessages,
    bool? canSendMedia,
    bool? isBanned,
    String? role,
  }) async {
    final collectionName = _getCollectionForRoom(roomId);
    final memberRef = _firestore.collection(collectionName).doc(roomId).collection('members').doc(userId);

    final updates = <String, dynamic>{};
    if (canSendMessages != null) updates['canSendMessages'] = canSendMessages;
    if (canSendMedia != null) updates['canSendMedia'] = canSendMedia;
    if (isBanned != null) updates['isBanned'] = isBanned;
    if (role != null) updates['role'] = role;

    if (updates.isNotEmpty) {
      await memberRef.set(updates, SetOptions(merge: true));
    }
  }

  /// Emits a stream of member maps from the `members` subcollection of a group room.
  Stream<List<Map<String, dynamic>>> getGroupMembersStream(String roomId) {
    final collectionName = _getCollectionForRoom(roomId);
    return _firestore
        .collection(collectionName)
        .doc(roomId)
        .collection('members')
        .snapshots()
        .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  /// Emits a stream of a specific user's member doc from `members/{userId}`.
  Stream<Map<String, dynamic>?> getGroupMemberPermissionsStream(String roomId, String userId) {
    final collectionName = _getCollectionForRoom(roomId);
    return _firestore
        .collection(collectionName)
        .doc(roomId)
        .collection('members')
        .doc(userId)
        .snapshots()
        .map((snap) => snap.data());
  }

  /// Bans a user from a group room (sets isBanned = true).
  Future<void> banUserFromGroup(String roomId, String userId) async {
    await updateUserGroupPermissions(roomId, userId, isBanned: true, canSendMessages: false, canSendMedia: false);
  }

  /// Unbans a user from a group room (sets isBanned = false).
  Future<void> unbanUserFromGroup(String roomId, String userId) async {
    await updateUserGroupPermissions(roomId, userId, isBanned: false, canSendMessages: true, canSendMedia: true);
  }

  /// Query for group session rooms belonging to the current user.
  Query<Map<String, dynamic>> groupSessionRoomsQuery(Timestamp? updateTime) {
    var query = _firestore
        .collection(_config.groupSessionRoomsCollection)
        .orderBy('updatedAt', descending: true)
        .where('userIds', arrayContains: currentUserId);

    if (updateTime != null && updateTime.millisecondsSinceEpoch > 0) {
      query = query.where('updatedAt', isGreaterThan: updateTime);
    }
    print('🔍 [FirebaseChatCore groupSessionRoomsQuery]');
    print('   - Collection: ${_config.groupSessionRoomsCollection}');
    print('   - UserID: $currentUserId');
    print('   - updateTime (Filter): ${updateTime?.toDate()} (${updateTime?.millisecondsSinceEpoch}ms)');
    print('   - Query Object: $query');
    return query;
  }

  /// Emits a stream of group session rooms for current user from configured group session collection.
  Stream<List<types.Room>> getGroupSessionRoomsStream() {
    late StreamController<List<types.Room>> controller;
    StreamSubscription? subscription;

    controller = StreamController<List<types.Room>>.broadcast(
      onListen: () async {
        // 1. Emit cached group rooms immediately upon subscription
        final listFromCache = await ChatCacheManager.instance.getCachedGroupRooms();
        if (!controller.isClosed && listFromCache.isNotEmpty) {
          controller.add(listFromCache);
        }

        final resolvedUpdateTime = listFromCache.isNotEmpty
            ? Timestamp.fromMillisecondsSinceEpoch(listFromCache.map((r) => r.updatedAt ?? 0).fold<int>(0, math.max))
            : null;

        // 2. Query Firestore and update cache + emit
        try {
          subscription = groupSessionRoomsQuery(resolvedUpdateTime).snapshots().listen(
            (snapshot) async {
              try {
                final rooms = await _processRoomsQuery(snapshot);
                if (rooms.isEmpty && listFromCache.isEmpty && !controller.isClosed) {
                  controller.add([]);
                  return;
                }
                if (rooms.isEmpty) return;

                await ChatCacheManager.instance.saveGroupRooms(rooms);
                final updatedCached = await ChatCacheManager.instance.getCachedGroupRooms();
                if (!controller.isClosed) controller.add(updatedCached);
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
          if (!controller.isClosed) controller.addError(e);
        }
      },
      onCancel: () {
        subscription?.cancel();
      },
    );

    return controller.stream;
  }

  /// Emits a stream of ALL group session rooms (for admin/monitoring), synchronized with Firestore and cached locally.
  Stream<List<types.Room>> getAllGroupSessionRoomsStream({Timestamp? updateTime}) {
    late StreamController<List<types.Room>> controller;
    StreamSubscription? subscription;

    controller = StreamController<List<types.Room>>.broadcast(
      onListen: () async {
        // 1. Emit cached group rooms immediately upon subscription
        final listFromCache = await ChatCacheManager.instance.getCachedGroupRooms(userId: ChatCacheBoxes.allGroupRoomsKey);
        if (!controller.isClosed && listFromCache.isNotEmpty) {
          controller.add(listFromCache);
        }

        final resolvedUpdateTime = updateTime ?? (listFromCache.isNotEmpty
            ? Timestamp.fromMillisecondsSinceEpoch(listFromCache.map((r) => r.updatedAt ?? 0).fold<int>(0, math.max))
            : null);

        // 2. Query Firestore and update cache + emit
        try {
          var query = _firestore
              .collection(_config.groupSessionRoomsCollection)
              .orderBy('updatedAt', descending: true);

          if (resolvedUpdateTime != null && resolvedUpdateTime.millisecondsSinceEpoch > 0) {
            query = query.where('updatedAt', isGreaterThan: resolvedUpdateTime);
          }

          subscription = query.snapshots().listen(
            (snapshot) async {
              try {
                final rooms = await _processRoomsQuery(snapshot);
                if (rooms.isNotEmpty) {
                  await ChatCacheManager.instance.saveGroupRooms(rooms, userId: ChatCacheBoxes.allGroupRoomsKey);
                  final updatedCached = await ChatCacheManager.instance.getCachedGroupRooms(userId: ChatCacheBoxes.allGroupRoomsKey);
                  if (!controller.isClosed) controller.add(updatedCached);
                } else if (listFromCache.isEmpty && !controller.isClosed) {
                  controller.add([]);
                }
              } catch (e, st) {
                print('❌ [FirebaseChatCore getAllGroupSessionRoomsStream Error]: $e');
                print(st);
                if (!controller.isClosed) controller.addError(e);
              }
            },
            onError: (err) {
              print('❌ [FirebaseChatCore getAllGroupSessionRoomsStream onError]: $err');
              if (!controller.isClosed) controller.addError(err);
            },
          );
        } catch (e) {
          print('❌ [FirebaseChatCore getAllGroupSessionRoomsStream catch]: $e');
          if (!controller.isClosed) controller.addError(e);
        }
      },
      onCancel: () {
        subscription?.cancel();
      },
    );

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
        await ChatCacheManager.instance.saveGroupRooms(rooms);
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
}
