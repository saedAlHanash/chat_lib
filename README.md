# Chat Lib

A clean, logic-only, and fully decoupled Flutter chat library that implements Firebase Firestore messaging with local caching powered by **Hive CE** (Community Edition).

مكتبة Dart/Flutter للمحادثة مع فصل كامل للمنطق البرمجي (Logic-only)، معتمدة على Firebase Firestore مع تخزين مؤقت محلي مدعوم بـ **Hive CE**.

---

## English Documentation

### Features
* **Logic-only:** 100% decoupled from any UI widgets.
* **Local Caching:** Rooms and messages are cached locally using Hive CE for offline capability and fast rendering.
* **Custom File Uploading:** No hard dependency on Firebase Storage. You can use any storage service by providing a custom `uploadDelegate`.
* **Real-time Syncing:** Merges live Firestore streams with local Hive cache seamlessly.
* **Read/Unread Tracking:** Built-in logic to determine read/unread status of rooms based on timestamps.

### Installation
Add the package path in your main project's `pubspec.yaml`:
```yaml
dependencies:
  chat_lib:
    path: ../packages/chat_lib
```

### Usage

#### 1. Initialization
Initialize the library (usually in `main.dart`) by providing the `FirebaseFirestore` instance, current user ID provider, and optional file upload delegate:

```dart
import 'package:chat_lib/chat_lib.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Initialize Chat Library
  FirebaseChatCore.instance.initialize(
    ChatConfig(
      firestore: FirebaseFirestore.instance,
      currentUserId: () => AppProvider.myId, // dynamically resolve current user id
      isTestMode: false, // Prepends 'test_' to collection names if true
      uploadDelegate: (filePath, {mimeType}) async {
        // Upload file to any service (e.g. S3, Firebase Storage, Custom Backend)
        // and return the remote URL.
        return await uploadMyFile(filePath);
      },
    ),
  );

  runApp(const MyApp());
}
```

#### 2. User Registration & Update
Save or update user details in Firestore:
```dart
final user = User(
  id: 'user_123',
  firstName: 'John',
  imageUrl: 'https://example.com/avatar.png',
  role: Role.user,
);

// Register user (creates document if not exists)
await FirebaseChatCore.instance.createUserInFirestore(user);

// Update user details
await FirebaseChatCore.instance.updateUser(user);
```

#### 3. Managing Rooms
Create or find direct chat rooms:
```dart
// Find or create a room with another user
final room = await FirebaseChatCore.instance.createRoom('other_user_id');

// Find existing room locally/online
final room = await FirebaseChatCore.instance.getRoomByUserId('other_user_id');
```

#### 4. Sending & Deleting Messages
Send text, images, files, or custom messages:
```dart
// Send a text message
await FirebaseChatCore.instance.sendMessage(
  const PartialText(text: 'Hello!'),
  room.id,
);

// Send an attachment (Library automatically uploads via uploadDelegate if the URI is a local path)
await FirebaseChatCore.instance.sendMessage(
  const PartialImage(
    name: 'photo.png',
    size: 2048,
    uri: '/local/path/to/photo.png', // Uploads and replaces with remote URL
  ),
  room.id,
);

// Delete a message (Soft delete)
await FirebaseChatCore.instance.deleteMessage(messageId, room.id);
```

#### 5. Real-time Streams with Local Caching
Listen to rooms and messages in real-time. Emits cached items instantly before fetching fresh updates from Firestore:
```dart
// Listen to all rooms
FirebaseChatCore.instance.getRoomsStream().listen((rooms) {
  // rooms list is sorted and cached
});

// Listen to messages of a room
FirebaseChatCore.instance.getMessagesStream(room.id).listen((messages) {
  // messages list is sorted (newest first) and cached
});
```

#### 6. Read / Unread Messages
Determine room status using helper extensions:
```dart
import 'package:chat_lib/chat_lib.dart';

// Mark room as read when entering/exiting the chat screen
await FirebaseChatCore.instance.latestSeenRoom(room);

// Set online status in room
await FirebaseChatCore.instance.setMyState(room, true);

// Check if room has unread messages
bool isUnread = room.isNotRead;
```

#### 7. Logout & Clear Cache
Logs out and clears all cached rooms and messages for the user:
```dart
await FirebaseChatCore.instance.logout();
```

---

## التوثيق باللغة العربية (Arabic Documentation)

### الميزات:
* **منطق عمل فقط (Logic-only):** مستقل تماماً عن أي واجهات أو ويدجت.
* **تخزين مؤقت محلي:** يتم حفظ الغرف والرسائل محلياً باستخدام Hive CE لتسريع الاستجابة والعمل أوفلاين.
* **مرونة رفع الملفات:** لا تعتمد المكتبة على خادم Firebase Storage بشكل صلب. يمكنك رفع الملفات لأي سيرفر عبر توفير `uploadDelegate` مخصص.
* **مزامنة حية:** تدمج التغييرات الفورية من Firestore مع البيانات المخزنة محلياً بسلاسة.
* **تحديد المقروء وغير المقروء:** منطق مدمج لفحص حالة قراءة الغرفة استناداً إلى طوابع وقت المشاهدة.

### التهيئة والاستخدام:

#### 1. تهيئة المكتبة
قم بتهيئة المكتبة (غالباً في ملف `main.dart`) عن طريق تمرير نسخة Firestore، وموفر معرّف المستخدم الحالي، ومفوض رفع الملفات الاختياري:

```dart
import 'package:chat_lib/chat_lib.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // تهيئة المكتبة
  FirebaseChatCore.instance.initialize(
    ChatConfig(
      firestore: FirebaseFirestore.instance,
      currentUserId: () => AppProvider.myId, // معرّف المستخدم الحالي ديناميكياً
      isTestMode: false, // في حال تفعيله، يضيف بادئة test_ للمجموعات
      uploadDelegate: (filePath, {mimeType}) async {
        // ارفع الملف لسيرفرك الخاص أو S3 وأرجع الرابط السحابي هنا
        return await myCustomUpload(filePath);
      },
    ),
  );

  runApp(const MyApp());
}
```

#### 2. تسجيل وتحديث المستخدمين
```dart
final user = User(
  id: 'user_123',
  firstName: 'أحمد',
  imageUrl: 'https://example.com/avatar.png',
  role: Role.user,
);

// تسجيل المستخدم لأول مرة
await FirebaseChatCore.instance.createUserInFirestore(user);

// تحديث ملف المستخدم
await FirebaseChatCore.instance.updateUser(user);
```

#### 3. إنشاء الغرف
```dart
// إنشاء أو جلب غرفة دردشة ثنائية مع مستخدم آخر
final room = await FirebaseChatCore.instance.createRoom('other_user_id');
```

#### 4. إرسال وحذف الرسائل
```dart
// إرسال رسالة نصية
await FirebaseChatCore.instance.sendMessage(
  const PartialText(text: 'مرحباً!'),
  room.id,
);

// إرسال مرفق (صورة، صوت، ملف). ستقوم المكتبة تلقائياً برفعه عبر الـ delegate إذا كان المسار محلياً
await FirebaseChatCore.instance.sendMessage(
  const PartialImage(
    name: 'image.jpg',
    size: 10240,
    uri: '/path/local/image.jpg',
  ),
  room.id,
);

// حذف الرسالة (حذف ناعم soft delete)
await FirebaseChatCore.instance.deleteMessage(messageId, room.id);
```

#### 5. الاستماع للغرف والرسائل مع التخزين المؤقت
```dart
// استماع حي لجميع الغرف (يجلب الكاش فوراً ثم يحدثه بالبيانات الحية)
FirebaseChatCore.instance.getRoomsStream().listen((rooms) {
  // القائمة مرتبة ومخزنة مؤقتاً
});

// استماع لرسائل غرفة معينة
FirebaseChatCore.instance.getMessagesStream(room.id).listen((messages) {
  // الرسائل مرتبة من الأحدث إلى الأقدم ومخزنة مؤقتاً
});
```

#### 6. تحديد الرسائل المقروءة والنشاط
```dart
// تحديث حالة رؤية الغرفة عند فتحها أو إغلاقها
await FirebaseChatCore.instance.latestSeenRoom(room);

// فحص وجود رسائل غير مقروءة للغرفة
bool hasUnread = room.isNotRead; // ملحق RoomLibExtension
```

#### 7. تسجيل الخروج ومسح الكاش
```dart
await FirebaseChatCore.instance.logout();
```
