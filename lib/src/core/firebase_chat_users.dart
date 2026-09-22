part of 'firebase_chat_core.dart';

/// Users operations extension on [FirebaseChatCore].
extension FirebaseChatUsers on FirebaseChatCore {
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
  /// Helper to convert a User DocumentSnapshot to types.User safely converting Timestamps.
  types.User _processUserDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    data['id'] = doc.id;
    data['createdAt'] = data['createdAt'] is Timestamp
        ? (data['createdAt'] as Timestamp).millisecondsSinceEpoch
        : (data['createdAt'] is num ? (data['createdAt'] as num).toInt() : (data['createdAt'] ?? 0));
    data['lastSeen'] = data['lastSeen'] is Timestamp
        ? (data['lastSeen'] as Timestamp).millisecondsSinceEpoch
        : (data['lastSeen'] is num ? (data['lastSeen'] as num).toInt() : (data['lastSeen'] ?? 0));
    final validRoles = ['admin', 'agent', 'moderator', 'user'];
    final rawRole = data['role']?.toString().toLowerCase();
    data['role'] = validRoles.contains(rawRole) ? rawRole : types.Role.user.name;
    data['updatedAt'] = data['updatedAt'] is Timestamp
        ? (data['updatedAt'] as Timestamp).millisecondsSinceEpoch
        : (data['updatedAt'] is num ? (data['updatedAt'] as num).toInt() : (data['updatedAt'] ?? 0));

    return types.User.fromJson(data);
  }

  List<types.User> _processUsersQuery(QuerySnapshot<Map<String, dynamic>> snapshot) {
    return snapshot.docs.map((doc) => _processUserDocument(doc)).toList();
  }

  /// Query for users in Firestore.
  Query<Map<String, dynamic>> _usersQuery(Timestamp? updateTime) {
    return _firestore
        .collection(_config.usersCollection)
        .orderBy('updatedAt', descending: true)
        .where('updatedAt', isGreaterThan: updateTime ?? Timestamp.fromMillisecondsSinceEpoch(0));
  }

  /// Emits a stream of users, synchronized with Firestore and cached locally via Hive.
  Stream<List<types.User>> getUsersStream({Timestamp? updateTime}) {
    late StreamController<List<types.User>> controller;
    StreamSubscription? subscription;

    controller = StreamController<List<types.User>>.broadcast(
      onListen: () async {
        // 1. Emit cached users immediately upon subscription
        final cached = await ChatCacheManager.instance.getCachedUsers();
        if (!controller.isClosed && cached.isNotEmpty) {
          controller.add(cached);
        }

        final resolvedUpdateTime = updateTime ?? Timestamp.fromMillisecondsSinceEpoch(cached.firstOrNull?.updatedAt ?? 0);

        // 2. Query Firestore and update cache + emit
        try {
          subscription = _usersQuery(resolvedUpdateTime).snapshots().listen(
            (snapshot) async {
              final usersList = _processUsersQuery(snapshot);

              final validUsers = usersList.where((u) => u.id != '0').toList();

              if (validUsers.isNotEmpty) {
                await ChatCacheManager.instance.saveUsers(validUsers);
                final updatedCached = await ChatCacheManager.instance.getCachedUsers();
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

  /// Deletes a user document from Firestore users collection and local cache.
  Future<void> deleteUser(String id) async {
    await _firestore.collection(_config.usersCollection).doc(id).delete();
    await ChatCacheManager.instance.deleteUserFromCache(id);
  }

  /// Helper to create a user with email.
  Future<bool> createMe(String id, String name, String email) async {
    try {
      await createUserInFirestore(
        types.User(
          id: id,
          firstName: name,
          imageUrl: '',
          lastName: '',
          role: types.Role.user,
          metadata: {'email': email},
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Retrieves a user profile from Firestore by ID.
  Future<types.User?> getUserFromFirestore(String userId) async {
    final doc = await _firestore.collection(_config.usersCollection).doc(userId).get();
    if (!doc.exists || doc.data() == null) return null;
    return _processUserDocument(doc);
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
}
