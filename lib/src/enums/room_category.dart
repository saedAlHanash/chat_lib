/// Represents the category of a chat room.
enum RoomCategory {
  /// Direct 1-on-1 chat room between two users
  direct,

  /// Standard group chat room
  group,

  /// Group session / subscription bundle group room
  groupSession;

  String toShortString() => name;

  static RoomCategory fromString(String? value) {
    switch (value) {
      case 'groupSession':
      case 'group_session':
        return RoomCategory.groupSession;
      case 'group':
        return RoomCategory.group;
      case 'direct':
      default:
        return RoomCategory.direct;
    }
  }
}
