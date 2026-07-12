import 'package:flutter_test/flutter_test.dart';
import 'package:chat_lib/chat_lib.dart';

void main() {
  test('FirebaseChatCore singleton instance test', () {
    final core = FirebaseChatCore.instance;
    expect(core, isNotNull);
  });
}
