part of 'firebase_chat_core.dart';

/// Direct (1-to-1) rooms operations extension on [FirebaseChatCore].
extension FirebaseChatRooms on FirebaseChatCore {
  /// Query for direct rooms belonging to current user.
  Query<Map<String, dynamic>> roomsQuery(Timestamp? updateTime) {
    var query = _firestore
        .collection(_config.roomsCollection)
        .orderBy('updatedAt', descending: true)
        .where('userIds', arrayContains: currentUserId);

    if (updateTime != null && updateTime.millisecondsSinceEpoch > 0) {
      query = query.where('updatedAt', isGreaterThan: updateTime);
    }
    return query;
  }

  /// Creates a direct chat room between the current user and [otherUserId].
  Future<types.Room> createRoom(String otherUserId) async {
    final userIds = [currentUserId, otherUserId]..sort();

    // Check existing room
    final querySnapshot = await _firestore
        .collection(_config.roomsCollection)
        .where('userIds', isEqualTo: userIds)
        .limit(1)
        .get();

    if (querySnapshot.docs.isNotEmpty) {
      final doc = querySnapshot.docs.first;
      final room = await _processRoomDocument(doc);
      await ChatCacheManager.instance.saveDirectRoom(room);
      return room;
    }

    // Create room
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
    await ChatCacheManager.instance.saveDirectRoom(room);
    return room;
  }

  /// Fetches an existing direct room by other user ID, or returns null.
  Future<types.Room?> getRoomByUserId(String otherUserId) async {
    final userIds = [currentUserId, otherUserId]..sort();

    final querySnapshot = await _firestore
        .collection(_config.roomsCollection)
        .where('userIds', isEqualTo: userIds)
        .limit(1)
        .get();

    if (querySnapshot.docs.isNotEmpty) {
      final doc = querySnapshot.docs.first;
      final room = await _processRoomDocument(doc);
      await ChatCacheManager.instance.saveDirectRoom(room);
      return room;
    }
    return null;
  }

  /// Emits a stream of direct rooms for the current user, synchronized with Firestore and cached locally.
  Stream<List<types.Room>> getRoomsStream({Timestamp? updateTime}) {
    late StreamController<List<types.Room>> controller;
    StreamSubscription? subscription;

    controller = StreamController<List<types.Room>>.broadcast(
      onListen: () async {
        // 1. Emit cached direct rooms immediately upon subscription
        final listFromCache = await ChatCacheManager.instance.getCachedDirectRooms();
        if (!controller.isClosed && listFromCache.isNotEmpty) {
          controller.add(listFromCache);
        }

        final resolvedUpdateTime =
            updateTime ??
            (listFromCache.isNotEmpty
                ? Timestamp.fromMillisecondsSinceEpoch(listFromCache.map((r) => r.updatedAt ?? 0).fold<int>(0, math.max))
                : null);

        // 2. Query Firestore and update cache + emit
        try {
          subscription = roomsQuery(resolvedUpdateTime).snapshots().listen(
            (snapshot) async {
              try {
                final rooms = await _processRoomsQuery(snapshot);
                if (rooms.isNotEmpty) {
                  await ChatCacheManager.instance.saveDirectRooms(rooms);
                  final updatedCached = await ChatCacheManager.instance.getCachedDirectRooms();
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
          if (!controller.isClosed) controller.addError(e);
        }
      },
      onCancel: () {
        subscription?.cancel();
      },
    );

    return controller.stream;
  }

  /// Emits a stream of ALL direct rooms (for admin/monitoring), synchronized with Firestore and cached locally.
  Stream<List<types.Room>> getAllRoomsStream({Timestamp? updateTime}) {
    late StreamController<List<types.Room>> controller;
    StreamSubscription? subscription;

    controller = StreamController<List<types.Room>>.broadcast(
      onListen: () async {
        // 1. Emit cached direct rooms immediately upon subscription
        final listFromCache = await ChatCacheManager.instance.getCachedDirectRooms(userId: ChatCacheBoxes.allRoomsKey);
        if (!controller.isClosed && listFromCache.isNotEmpty) {
          controller.add(listFromCache);
        }

        final resolvedUpdateTime =
            updateTime ??
            (listFromCache.isNotEmpty
                ? Timestamp.fromMillisecondsSinceEpoch(listFromCache.map((r) => r.updatedAt ?? 0).fold<int>(0, math.max))
                : null);

        // 2. Query Firestore and update cache + emit
        try {
          var query = _firestore.collection(_config.roomsCollection).orderBy('updatedAt', descending: true);

          if (resolvedUpdateTime != null && resolvedUpdateTime.millisecondsSinceEpoch > 0) {
            query = query.where('updatedAt', isGreaterThan: resolvedUpdateTime);
          }

          subscription = query.snapshots().listen(
            (snapshot) async {
              try {
                final rooms = await _processRoomsQuery(snapshot);
                if (rooms.isNotEmpty) {
                  await ChatCacheManager.instance.saveDirectRooms(rooms, userId: ChatCacheBoxes.allRoomsKey);
                  final updatedCached = await ChatCacheManager.instance.getCachedDirectRooms(userId: ChatCacheBoxes.allRoomsKey);
                  if (!controller.isClosed) controller.add(updatedCached);
                } else if (listFromCache.isEmpty && !controller.isClosed) {
                  controller.add([]);
                }
              } catch (e, st) {
                print('❌ [FirebaseChatCore getAllRoomsStream Error]: $e');
                print(st);
                if (!controller.isClosed) controller.addError(e);
              }
            },
            onError: (err) {
              print('❌ [FirebaseChatCore getAllRoomsStream onError]: $err');
              if (!controller.isClosed) controller.addError(err);
            },
          );
        } catch (e) {
          print('❌ [FirebaseChatCore getAllRoomsStream catch]: $e');
          if (!controller.isClosed) controller.addError(e);
        }
      },
      onCancel: () {
        subscription?.cancel();
      },
    );

    return controller.stream;
  }

  /// Direct one-time fetch of direct rooms for the current user from Firestore.
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
        await ChatCacheManager.instance.saveDirectRooms(rooms);
      }
      return rooms;
    } catch (e, st) {
      print('❌ [FirebaseChatCore getRooms Error]: $e');
      print(st);
      rethrow;
    }
  }
}
