part of 'firebase_chat_core.dart';

/// Group session rooms operations extension on [FirebaseChatCore].
extension FirebaseChatGroupRooms on FirebaseChatCore {
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

    // 1. Emit cached group rooms immediately
    final listFromCache = await ChatCacheManager.instance.getCachedGroupRooms(currentUserId);
    if (!controller.isClosed && listFromCache.isNotEmpty) {
      Future(() {
        controller.add(listFromCache);
      });
    }

    final updateTime = Timestamp.fromMillisecondsSinceEpoch(listFromCache.firstOrNull?.updatedAt ?? 0);

    // 2. Query Firestore and update cache + emit
    StreamSubscription? subscription;

    try {
      subscription = groupSessionRoomsQuery(updateTime).snapshots().listen(
        (snapshot) async {
          try {
            final rooms = await _processRoomsQuery(snapshot);
            if (rooms.isEmpty) return;

            await ChatCacheManager.instance.saveRooms(currentUserId, rooms, isGroup: true);
            final updatedCached = await ChatCacheManager.instance.getCachedGroupRooms(currentUserId);
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
        await ChatCacheManager.instance.saveRooms(currentUserId, rooms, isGroup: true);
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
