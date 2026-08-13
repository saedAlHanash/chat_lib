part of 'firebase_chat_core.dart';

/// Internal document processing and log helpers extension on [FirebaseChatCore].
extension FirebaseChatHelpers on FirebaseChatCore {
  String _getCollectionForRoom(String roomId, {RoomCategory? category}) {
    if (category == RoomCategory.groupSession || roomId.startsWith('group_bundle_') || RegExp(r'^\d+$').hasMatch(roomId)) {
      return _config.groupSessionRoomsCollection;
    }
    return _config.roomsCollection;
  }

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

  /// Helper to process a QuerySnapshot into a list of messages.
  Future<List<Map<String, dynamic>>> _processMessagesQuery(QuerySnapshot<Map<String, dynamic>> snapshot) async {
    final futures = snapshot.docs.map((doc) => _processMessageDocument(doc));
    return await Future.wait(futures);
  }

  /// Helper to process a single message document snapshot.
  Future<Map<String, dynamic>> _processMessageDocument(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data() ?? {};
    final authorId = data['authorId'] as String?;
    if (authorId != null) {
      final author = await fetchUser(authorId);
      data['author'] = author.toJson();
    }
    data['createdAt'] = data['createdAt'] is Timestamp
        ? (data['createdAt'] as Timestamp).millisecondsSinceEpoch
        : (data['createdAt'] ?? 0);
    data['id'] = doc.id;
    data['updatedAt'] = data['updatedAt'] is Timestamp
        ? (data['updatedAt'] as Timestamp).millisecondsSinceEpoch
        : (data['updatedAt'] ?? 0);
    return data;
  }
}
