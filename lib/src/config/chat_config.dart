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

  /// Name of the users collection in Firestore (default: 'users').
  final String usersCollectionName;

  /// If set to true, prepends 'test_' to the Firestore collection names.
  final bool isTestMode;

  /// Delegate callback to handle file uploading.
  /// When a message with local attachments (image, audio, file) is sent, the library
  /// calls this delegate to upload the file to any storage service (e.g. custom server, S3, Firebase Storage)
  /// and returns the uploaded file URL.
  final Future<String> Function(String filePath, {String? mimeType})? uploadDelegate;

  ChatConfig({
    required this.firestore,
    required this.currentUserId,
    this.roomsCollectionName = 'rooms',
    this.usersCollectionName = 'users',
    this.isTestMode = false,
    this.uploadDelegate,
  });

  /// Helper to get rooms collection name with test prefix if test mode is enabled
  String get roomsCollection => '${isTestMode ? 'test_' : ''}$roomsCollectionName';

  /// Helper to get users collection name with test prefix if test mode is enabled
  String get usersCollection => '${isTestMode ? 'test_' : ''}$usersCollectionName';
}
