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
}
