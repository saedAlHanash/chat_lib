import 'package:cloud_firestore/cloud_firestore.dart';

/// Configuration for the chat library.
/// Defines firestore instance, collection names, current user resolution,
/// test mode status, and optional file upload delegation.
class ChatConfig {
  /// The Firestore instance to use.
  final FirebaseFirestore firestore;

  /// Callback to dynamically resolve the current user's ID.
  /// Using a callback ensures that when a user logs out/in, the library can
  /// automatically resolve the updated user ID without re-initialization.
  final String Function() currentUserId;

  /// Name of the rooms collection in Firestore (default: 'rooms').
  final String roomsCollectionName;

  /// Name of the group session rooms collection in Firestore (default: 'group_rooms').
  final String groupSessionRoomsCollectionName;

  /// Name of the users collection in Firestore (default: 'users').
  final String usersCollectionName;

  /// If set to true, prepends 'test_' to the Firestore collection names.
  final bool isTestMode;

  /// Delegate callback to handle file uploading.
  final Future<String> Function(String filePath, {String? mimeType, Map<String, dynamic>? customArgs})? uploadDelegate;

  /// Cache schema version. If incremented, local cache will be automatically purged and re-synced.
  final int cacheVersion;

  /// Optional bundled JSON asset path for direct rooms seed (e.g. 'assets/seed/direct_rooms_seed.json').
  final String? directRoomsSeedAssetPath;

  /// Optional bundled JSON asset path for group rooms seed (e.g. 'assets/seed/group_rooms_seed.json').
  final String? groupRoomsSeedAssetPath;

  /// Optional bundled JSON asset path for users seed (e.g. 'assets/seed/users_seed.json').
  final String? usersSeedAssetPath;

  ChatConfig({
    required this.firestore,
    required this.currentUserId,
    this.roomsCollectionName = 'rooms',
    this.groupSessionRoomsCollectionName = 'group_rooms',
    this.usersCollectionName = 'users',
    this.isTestMode = false,
    this.cacheVersion = 1,
    this.directRoomsSeedAssetPath,
    this.groupRoomsSeedAssetPath,
    this.usersSeedAssetPath,
    this.uploadDelegate,
  });

  /// Helper to get rooms collection name with test prefix if test mode is enabled
  String get roomsCollection => '${isTestMode ? 'test_' : ''}$roomsCollectionName';

  /// Helper to get group session rooms collection name with test prefix if test mode is enabled
  String get groupSessionRoomsCollection => '${isTestMode ? 'test_' : ''}$groupSessionRoomsCollectionName';

  /// Helper to get users collection name with test prefix if test mode is enabled
  String get usersCollection => '${isTestMode ? 'test_' : ''}$usersCollectionName';
}
