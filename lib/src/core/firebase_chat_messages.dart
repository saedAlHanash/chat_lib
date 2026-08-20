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

  /// Updates / edits a text message.
  Future<void> updateMessage(types.Message message, String roomId) async {
    if (message is! types.TextMessage) {
      throw StateError('يسمح بتعديل الرسائل النصية فقط.');
    }
    final collection = _getCollectionForRoom(roomId);
    final msgDocRef = _firestore.collection('$collection/$roomId/messages').doc(message.id);
    final msgSnap = await msgDocRef.get();
    if (!msgSnap.exists) {
      throw StateError('الرسالة غير موجودة.');
    }

    final msgData = msgSnap.data() ?? {};
    final authorId = msgData['authorId']?.toString();
    if (authorId != currentUserId) {
      throw StateError('يمكنك تعديل رسائلك فقط.');
    }

    // Check permissions
    final memberDoc = await _firestore.collection('$collection/$roomId/members').doc(currentUserId).get();
    bool isAdmin = false;
    if (memberDoc.exists) {
      final perms = memberDoc.data() ?? {};
      if (perms['role'] == 'admin') {
        isAdmin = true;
      }
      if (perms['isBanned'] == true || perms['canSendMessages'] == false) {
        throw StateError('غير مسموح لك بتعديل أو إرسال الرسائل في هذه المجموعة.');
      }
    }

    // 5-minute limit check for non-admin students
    if (!isAdmin) {
      final createdAtTimestamp = msgData['createdAt'] as Timestamp?;
      final createdAtMillis = createdAtTimestamp?.millisecondsSinceEpoch ??
          (msgData['createdAt'] is num ? (msgData['createdAt'] as num).toInt() : 0);
      final nowMillis = DateTime.now().millisecondsSinceEpoch;

      if (createdAtMillis > 0 && (nowMillis - createdAtMillis) > 5 * 60 * 1000) {
        throw StateError('لا يمكن تعديل الرسالة بعد مرور أكثر من 5 دقائق.');
      }
    }

    final metadata = Map<String, dynamic>.from(msgData['metadata'] as Map? ?? {});
    metadata['isEdited'] = true;

    await msgDocRef.update({
      'text': message.text,
      'updatedAt': FieldValue.serverTimestamp(),
      'metadata': metadata,
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
    late StreamController<List<types.Message>> controller;
    StreamSubscription? subscription;

    controller = StreamController<List<types.Message>>.broadcast(
      onListen: () async {
        // 1. Emit cached messages immediately upon subscription
        final cached = await ChatCacheManager.instance.getCachedMessages(roomId);
        if (!controller.isClosed && cached.isNotEmpty) {
          cached.sort((a, b) => (b.createdAt ?? 0).compareTo(a.createdAt ?? 0));
          controller.add(cached);
        }

        final resolvedUpdateTime = updateTime ?? Timestamp.fromMillisecondsSinceEpoch(cached.firstOrNull?.updatedAt ?? 0);

        // 2. Query Firestore and update cache + emit
        try {
          subscription = messagesQuery(resolvedUpdateTime, roomId).snapshots().listen(
            (snapshot) async {
              final messagesList = await _processMessagesQuery(snapshot);

              if (messagesList.isNotEmpty) {
                await ChatCacheManager.instance.saveMessages(roomId, messagesList);
                final updatedCached = await ChatCacheManager.instance.getCachedMessages(roomId);
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
          if (!controller.isClosed) controller.addError(e);
        }
      },
      onCancel: () {
        subscription?.cancel();
      },
    );

    return controller.stream;
  }
}
