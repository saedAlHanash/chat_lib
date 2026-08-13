part of 'firebase_chat_core.dart';

/// Messages operations extension on [FirebaseChatCore].
extension FirebaseChatMessages on FirebaseChatCore {
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
}
