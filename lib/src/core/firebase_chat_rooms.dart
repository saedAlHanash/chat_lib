part of 'firebase_chat_core.dart';

/// Direct (1-to-1) rooms operations extension on [FirebaseChatCore].
extension FirebaseChatRooms on FirebaseChatCore {
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
        .where('userIds', isEqualTo: userIds)
        .limit(1)
        .get();

    final rooms = await _processRoomsQuery(result);
    return rooms.firstOrNull;
  }

  /// Retrieves a room by its ID.
  Future<types.Room?> getRoomByRoomId(String roomId) async {
    final collection = _getCollectionForRoom(roomId);
    final docSnap = await _firestore.collection(collection).doc(roomId).get();

    if (!docSnap.exists) return null;

    final room = await _processRoomDocument(docSnap);
    return room;
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

  /// Updates the latest seen timestamp for the current user in a room.
  Future<void> latestSeenRoom(types.Room room) async {
    final collection = _getCollectionForRoom(room.id);
    try {
      await _firestore.collection(collection).doc(room.id).update({
        'latestSeen$currentUserId': FieldValue.serverTimestamp(),
        'isOnline$currentUserId': false,
      });
    } catch (_) {}

    // Update local metadata
    final metadata = Map<String, dynamic>.from(room.metadata ?? {});
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    metadata['latestSeen'] = nowMillis;
    metadata['latestSeen$currentUserId'] = nowMillis;

    final updatedRoom = room.copyWith(metadata: metadata);
    final isGroup = room.type == types.RoomType.group || RegExp(r'^\d+$').hasMatch(room.id);
    await ChatCacheManager.instance.saveRoom(currentUserId, updatedRoom);
    if (isGroup) {
      await ChatCacheManager.instance.saveRooms(currentUserId, [updatedRoom], isGroup: true);
    }
  }

  /// Sets the current user's online state in a room.
  Future<void> setMyState(types.Room room, bool isOnline) async {
    final collection = _getCollectionForRoom(room.id);
    try {
      await _firestore.collection(collection).doc(room.id).update({'isOnline$currentUserId': isOnline});
    } catch (_) {}
  }

  /// Emits a stream of rooms for the current user, synchronized with Firestore and cached locally.
  Future<Stream<List<types.Room>>> getRoomsStream({Timestamp? updateTime}) async {
    final controller = StreamController<List<types.Room>>.broadcast();

    // 1. Emit cached direct rooms immediately
    final listFromCache = await ChatCacheManager.instance.getCachedRooms(currentUserId);
    if (!controller.isClosed && listFromCache.isNotEmpty) {
      controller.add(listFromCache);
    }

    final resolvedUpdateTime = updateTime ?? (listFromCache.isNotEmpty
        ? Timestamp.fromMillisecondsSinceEpoch(listFromCache.firstOrNull?.updatedAt ?? 0)
        : null);

    // 2. Query Firestore and update cache + emit
    StreamSubscription? subscription;
    try {
      subscription = roomsQuery(resolvedUpdateTime).snapshots().listen(
        (snapshot) async {
          try {
            final rooms = await _processRoomsQuery(snapshot);
            if (rooms.isNotEmpty) {
              await ChatCacheManager.instance.saveRooms(currentUserId, rooms, isGroup: false);
              final updatedCached = await ChatCacheManager.instance.getCachedRooms(currentUserId);
              if (!controller.isClosed) controller.add(updatedCached);
            } else if (listFromCache.isEmpty && !controller.isClosed) {
              controller.add([]);
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
        await ChatCacheManager.instance.saveRooms(currentUserId, rooms, isGroup: false);
      }
      return rooms;
    } catch (e, st) {
      print('❌ [FirebaseChatCore getRooms Error]: $e');
      print(st);
      rethrow;
    }
  }
}
