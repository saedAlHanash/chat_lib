part of 'firebase_chat_core.dart';

/// Common room operations extension on [FirebaseChatCore] that apply to both direct and group rooms.
extension FirebaseChatCommonRooms on FirebaseChatCore {
  /// Fetches a room by its document ID (automatically detects direct or group room).
  Future<types.Room?> getRoomByRoomId(String roomId) async {
    final collection = _getCollectionForRoom(roomId);
    final docSnap = await _firestore.collection(collection).doc(roomId).get();

    if (!docSnap.exists) return null;

    final room = await _processRoomDocument(docSnap);
    if (room.isGroup) {
      await ChatCacheManager.instance.saveGroupRoom(room);
      if (currentUserId != ChatCacheBoxes.allGroupRoomsKey) {
        await ChatCacheManager.instance.saveGroupRoom(room, userId: ChatCacheBoxes.allGroupRoomsKey);
      }
    } else {
      await ChatCacheManager.instance.saveDirectRoom(room);
      if (currentUserId != ChatCacheBoxes.allRoomsKey) {
        await ChatCacheManager.instance.saveDirectRoom(room, userId: ChatCacheBoxes.allRoomsKey);
      }
    }
    return room;
  }

  /// Updates the latest seen timestamp for the current user in a room (direct or group).
  Future<types.Room> latestSeenRoom(types.Room room) async {
    final collection = _getCollectionForRoom(room.id);
    try {
      _firestore.collection(collection).doc(room.id).update({
        'latestSeen$currentUserId': FieldValue.serverTimestamp(),
        'isOnline$currentUserId': false,
      });
    } catch (e) {
      print('❌ [latestSeenRoom]: $e');
    }

    // Update local metadata
    final metadata = Map<String, dynamic>.from(room.metadata ?? {});
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    metadata['latestSeen'] = nowMillis;
    metadata['latestSeen$currentUserId'] = nowMillis;

    final updatedRoom = room.copyWith(metadata: metadata);

    // Save to Hive cache for current user and all_rooms
    if (updatedRoom.isGroup) {
      await ChatCacheManager.instance.saveGroupRoom(updatedRoom);
      if (currentUserId != ChatCacheBoxes.allGroupRoomsKey) {
        await ChatCacheManager.instance.saveGroupRoom(updatedRoom, userId: ChatCacheBoxes.allGroupRoomsKey);
      }
    } else {
      await ChatCacheManager.instance.saveDirectRoom(updatedRoom);
      if (currentUserId != ChatCacheBoxes.allRoomsKey) {
        await ChatCacheManager.instance.saveDirectRoom(updatedRoom, userId: ChatCacheBoxes.allRoomsKey);
      }
    }
    return updatedRoom;
  }

  /// Sets the current user's online state in a room (direct or group).
  Future<void> setMyState(types.Room room, bool isOnline) async {
    final collection = _getCollectionForRoom(room.id);
    try {
      await _firestore.collection(collection).doc(room.id).update({'isOnline$currentUserId': isOnline});
    } catch (_) {}
  }

  /// Deletes a room document and clears local cache (direct or group).
  Future<void> deleteRoom(String roomId) async {
    final collection = _getCollectionForRoom(roomId);
    await _firestore.collection(collection).doc(roomId).delete();
    await ChatCacheManager.instance.deleteDirectRoomFromCache(roomId);
    await ChatCacheManager.instance.deleteGroupRoomFromCache(roomId);
    if (currentUserId != ChatCacheBoxes.allRoomsKey) {
      await ChatCacheManager.instance.deleteDirectRoomFromCache(roomId, userId: ChatCacheBoxes.allRoomsKey);
    }
    if (currentUserId != ChatCacheBoxes.allGroupRoomsKey) {
      await ChatCacheManager.instance.deleteGroupRoomFromCache(roomId, userId: ChatCacheBoxes.allGroupRoomsKey);
    }
  }
}
