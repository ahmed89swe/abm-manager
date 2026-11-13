import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';
import '../models/app_user.dart';
import '../models/monthly_box.dart';
import '../services/audit_helper.dart';
import '../services/notification_service.dart';
import '../services/receipt_storage_service.dart';

class AuthRepository {
  AuthRepository({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Stream<AppUser?> watchUserProfile(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return AppUser.fromMap(doc.data()!, doc.id);
    });
  }

  Future<AppUser?> fetchUserProfile(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists || doc.data() == null) return null;
    return AppUser.fromMap(doc.data()!, doc.id);
  }

  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final firebaseUser = cred.user!;
    final uid = firebaseUser.uid;
    final userRef = _firestore.collection('users').doc(uid);
    final userSnap = await userRef.get();
    var profile = (userSnap.exists && userSnap.data() != null)
        ? AppUser.fromMap(userSnap.data()!, uid)
        : null;

    if (profile == null) {
      // حساب مدير مضاف مسبقاً في Firebase Authentication أو أول تهيئة
      final fallbackName =
          (firebaseUser.displayName?.trim().isNotEmpty ?? false)
          ? firebaseUser.displayName!.trim()
          : email.trim().split('@').first;
      final manager = AppUser(
        uid: uid,
        managerId: uid,
        name: fallbackName,
        email: email.trim(),
        phone: firebaseUser.phoneNumber ?? '',
        role: UserRole.manager,
        isActive: true,
      );

      final bootstrapRef = _firestore.collection('app_config').doc('bootstrap');
      final bootstrapSnap = await bootstrapRef.get();

      final batch = _firestore.batch();
      batch.set(userRef, {
        ...manager.toMap(),
        'legacyMigrated': bootstrapSnap.exists,
      });
      if (!bootstrapSnap.exists) {
        batch.set(bootstrapRef, {
          'managerUid': uid,
          'managerEmail': manager.email,
          'initializedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();

      await AuditHelper.recordLog(
        firestore: _firestore,
        actor: manager,
        actionType: 'manager_bootstrap',
        descriptionAr: 'تم ربط حساب المدير المجهز مسبقاً: ${manager.email}',
        descriptionEn:
            'Linked pre-configured manager account: ${manager.email}',
      );
      profile = manager;
    } else {
      final rawData = userSnap.data()!;
      // إذا أُضيف مستند المدير يدوياً في Firestore بدون managerId أو uid/email
      if (profile.isManager &&
          ((rawData['managerId'] as String? ?? '').isEmpty ||
              (rawData['uid'] as String? ?? '').isEmpty ||
              (rawData['email'] as String? ?? '').isEmpty)) {
        await userRef.update({
          'uid': uid,
          'managerId': uid,
          if ((rawData['email'] as String? ?? '').isEmpty)
            'email': firebaseUser.email ?? email.trim(),
          if ((rawData['name'] as String? ?? '').isEmpty)
            'name': email.trim().split('@').first,
          if (!rawData.containsKey('isActive')) 'isActive': true,
        });
        profile = profile.copyWith(managerId: uid);
      } else if (profile.isDelegate &&
          (profile.managerId == null || profile.managerId!.isEmpty)) {
        // ربط المندوبين القدامى (قبل دعم تعدد المدراء) بالمدير الأول المسجل في bootstrap
        final bootstrapSnap = await _firestore
            .collection('app_config')
            .doc('bootstrap')
            .get();
        final legacyManagerUid =
            bootstrapSnap.data()?['managerUid'] as String? ?? '';
        if (legacyManagerUid.isNotEmpty) {
          await userRef.update({'managerId': legacyManagerUid});
          profile = profile.copyWith(managerId: legacyManagerUid);
        }
      }
    }

    if (!profile.isActive) {
      await _auth.signOut();
      throw StateError('تم إيقاف هذا الحساب من قبل المدير.');
    }

    if (profile.isManager) {
      await ensureManagerWorkspaceMigrated(profile);
    }

    return profile;
  }

  Future<void> signOut() async {
    await NotificationService.instance.detachListener();
    await _auth.signOut();
  }

  /// تحديث الملف الشخصي (الاسم الشخصي والهاتف والصورة الشخصية) للمدير والمندوبين
  Future<void> updateProfile({
    required AppUser user,
    required String name,
    required String phone,
    String? avatarBase64,
    PickedImageData? avatarImage,
  }) async {
    String? photoUrl = user.photoUrl;
    if (avatarImage != null) {
      try {
        photoUrl = await ReceiptStorageService.instance.uploadReceipt(
          image: avatarImage,
          folder: 'avatars',
          referenceId: user.uid,
        );
      } catch (_) {
        // نحتفظ بـ avatarBase64 المضغوط حتى لو لم يتم تفعيل Storage
      }
    }

    final updateData = <String, dynamic>{
      'name': name.trim(),
      'phone': phone.trim(),
      'photoUrl': ?photoUrl,
      'avatarBase64': ?avatarBase64,
    };

    await _firestore.collection('users').doc(user.uid).update(updateData);

    await AuditHelper.recordLog(
      firestore: _firestore,
      actor: user.copyWith(name: name.trim()),
      actionType: 'update_profile',
      descriptionAr: 'حدّث ${user.name} ملفه الشخصي ($name)',
      descriptionEn: '${user.name} updated profile ($name)',
    );
  }

  /// ترحيل بيانات المدير الأساسي القديمة مرة واحدة لتوسيمها بـ managerId لضمان عدم ضياعها مع تعدد المدراء
  Future<void> ensureManagerWorkspaceMigrated(AppUser user) async {
    if (!user.isManager) return;
    final uid = user.uid;
    final userRef = _firestore.collection('users').doc(uid);
    final userSnap = await userRef.get();
    final userData = userSnap.data();
    if (userData == null) return;
    if (userData['legacyMigrated'] == true) return;

    final bootstrapSnap = await _firestore
        .collection('app_config')
        .doc('bootstrap')
        .get();
    final legacyPrimaryUid = bootstrapSnap.data()?['managerUid'] as String?;

    if (legacyPrimaryUid == null || legacyPrimaryUid != uid) {
      await userRef.update({'managerId': uid, 'legacyMigrated': true});
      return;
    }

    Future<void> flushBatchOps(List<void Function(WriteBatch b)> ops) async {
      const chunkSize = 400;
      for (var i = 0; i < ops.length; i += chunkSize) {
        final chunk = ops.sublist(
          i,
          (i + chunkSize) > ops.length ? ops.length : i + chunkSize,
        );
        final batch = _firestore.batch();
        for (final op in chunk) {
          op(batch);
        }
        await batch.commit();
      }
    }

    final ops = <void Function(WriteBatch b)>[];

    const simpleCollections = [
      'governorates',
      'materials',
      'box_transactions',
      'invoices',
      'personal_expenses',
      'audit_logs',
    ];
    for (final colName in simpleCollections) {
      final snap = await _firestore.collection(colName).get();
      for (final doc in snap.docs) {
        final data = doc.data();
        final currentManagerId = (data['managerId'] as String?) ?? '';
        if (currentManagerId.isEmpty) {
          ops.add((b) => b.update(doc.reference, {'managerId': uid}));
        }
      }
    }

    // المندوبون القدامى بدون managerId
    final delegatesSnap = await _firestore
        .collection('users')
        .where('role', isEqualTo: UserRole.delegate.value)
        .get();
    for (final doc in delegatesSnap.docs) {
      final currentManagerId = (doc.data()['managerId'] as String?) ?? '';
      if (currentManagerId.isEmpty) {
        ops.add((b) => b.update(doc.reference, {'managerId': uid}));
      }
    }

    // الإشعارات القديمة
    final notifsSnap = await _firestore.collection('notifications').get();
    for (final doc in notifsSnap.docs) {
      final data = doc.data();
      final currentManagerId = (data['managerId'] as String?) ?? '';
      if (currentManagerId.isEmpty) {
        final oldTags = List<String>.from(data['audienceTags'] ?? const []);
        final newTags = oldTags.map((t) {
          if (t == 'MANAGERS') return 'MANAGER_$uid';
          if (t == 'ALL') return 'ALL_$uid';
          return t;
        }).toList();
        ops.add(
          (b) => b.update(doc.reference, {
            'managerId': uid,
            'audienceTags': newTags,
          }),
        );
      }
    }

    // الصناديق الشهرية للمدير: نقل من {YYYY-MM} إلى {uid}_{YYYY-MM}
    final monthlySnap = await _firestore
        .collection('manager_monthly_boxes')
        .get();
    for (final doc in monthlySnap.docs) {
      final data = doc.data();
      final currentManagerId = (data['managerId'] as String?) ?? '';
      if (currentManagerId.isEmpty) {
        final rawKey = (data['monthKey'] as String?) ?? '';
        final monthKey = rawKey.isNotEmpty
            ? rawKey
            : (doc.id.contains('_') ? doc.id.split('_').last : doc.id);
        final targetId = MonthlyBox.docId(uid, monthKey);
        final targetRef = _firestore
            .collection('manager_monthly_boxes')
            .doc(targetId);
        ops.add(
          (b) => b.set(targetRef, {
            ...data,
            'monthKey': monthKey,
            'managerId': uid,
          }, SetOptions(merge: true)),
        );
        if (doc.id != targetId) {
          ops.add((b) => b.delete(doc.reference));
        }
      }
    }

    // الصناديق الشهرية للمحافظات: نقل من {govId}_{YYYY-MM} إلى {uid}_{govId}_{YYYY-MM}
    final govBoxesSnap = await _firestore
        .collection('governorate_monthly_boxes')
        .get();
    for (final doc in govBoxesSnap.docs) {
      final data = doc.data();
      final currentManagerId = (data['managerId'] as String?) ?? '';
      if (currentManagerId.isEmpty) {
        final govId = (data['governorateId'] as String?) ?? '';
        final monthKey = (data['monthKey'] as String?) ?? '';
        if (govId.isNotEmpty && monthKey.isNotEmpty) {
          final targetId = GovernorateMonthlyBox.docId(uid, govId, monthKey);
          final targetRef = _firestore
              .collection('governorate_monthly_boxes')
              .doc(targetId);
          ops.add(
            (b) => b.set(targetRef, {
              ...data,
              'managerId': uid,
            }, SetOptions(merge: true)),
          );
          if (doc.id != targetId) {
            ops.add((b) => b.delete(doc.reference));
          }
        }
      }
    }

    ops.add(
      (b) => b.update(userRef, {'managerId': uid, 'legacyMigrated': true}),
    );

    await flushBatchOps(ops);
  }

  /// إنشاء حساب مدير جديد معزول البيانات (يمكن إنشاء أكثر من مدير)
  Future<AppUser> setupPrimaryManager({
    required String name,
    required String email,
    required String password,
    required String phone,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final uid = cred.user!.uid;
    final bootstrapRef = _firestore.collection('app_config').doc('bootstrap');
    final bootstrapSnap = await bootstrapRef.get();

    final user = AppUser(
      uid: uid,
      managerId: uid,
      name: name.trim(),
      email: email.trim(),
      phone: phone.trim(),
      role: UserRole.manager,
      isActive: true,
    );
    final batch = _firestore.batch();
    batch.set(_firestore.collection('users').doc(uid), {
      ...user.toMap(),
      'legacyMigrated': true,
    });
    if (!bootstrapSnap.exists) {
      batch.set(bootstrapRef, {
        'managerUid': uid,
        'managerEmail': user.email,
        'initializedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();

    await AuditHelper.recordLog(
      firestore: _firestore,
      actor: user,
      actionType: 'manager_setup',
      descriptionAr: 'تم إنشاء حساب مدير مستقل: ${user.name}',
      descriptionEn: 'Independent manager account created: ${user.name}',
    );
    return user;
  }

  /// إنشاء حساب مندوب جديد من داخل حساب المدير بدون تسجيل خروج المدير
  Future<AppUser> createDelegateAccount({
    required AppUser manager,
    required String name,
    required String email,
    required String password,
    required String phone,
    required String governorateId,
    required String governorateName,
    double initialVirtualBalance = 0,
  }) async {
    FirebaseApp? secondaryApp;
    try {
      secondaryApp = await Firebase.initializeApp(
        name:
            'SecondaryDelegateCreator_${DateTime.now().millisecondsSinceEpoch}',
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      final cred = await secondaryAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final delegateUid = cred.user!.uid;
      await secondaryAuth.signOut();

      final managerId = manager.effectiveManagerId;
      final delegate = AppUser(
        uid: delegateUid,
        managerId: managerId,
        name: name.trim(),
        email: email.trim(),
        phone: phone.trim(),
        role: UserRole.delegate,
        governorateId: governorateId,
        governorateName: governorateName,
        virtualBoxBalance: initialVirtualBalance,
        isActive: true,
      );

      await _firestore
          .collection('users')
          .doc(delegateUid)
          .set(delegate.toMap());

      await AuditHelper.recordLog(
        firestore: _firestore,
        actor: manager,
        actionType: 'create_delegate',
        descriptionAr:
            'أنشأ المدير حساب مندوب جديد: ${delegate.name} لمحافظة $governorateName برصيد افتراضي $initialVirtualBalance',
        descriptionEn:
            'Manager created delegate ${delegate.name} for $governorateName with balance $initialVirtualBalance',
        metadata: {
          'delegateId': delegateUid,
          'governorateId': governorateId,
          'initialBalance': initialVirtualBalance,
        },
      );

      await NotificationService.instance.sendCloudNotification(
        managerId: managerId,
        titleAr: 'تم إنشاء حساب مندوب جديد',
        titleEn: 'New Delegate Account Created',
        bodyAr: 'تم تسجيل المندوب ${delegate.name} لمحافظة $governorateName',
        bodyEn: 'Delegate ${delegate.name} assigned to $governorateName',
        type: 'delegate_created',
        targetRole: 'delegate',
        audienceTags: ['MANAGER_$managerId', 'USER_$delegateUid'],
        targetUserIds: [delegateUid],
        referenceId: delegateUid,
        createdByUid: manager.uid,
      );

      return delegate;
    } finally {
      await secondaryApp?.delete();
    }
  }

  Stream<List<AppUser>> watchAllDelegates(String managerId) {
    if (managerId.isEmpty) return Stream.value(const []);
    return _firestore
        .collection('users')
        .where('managerId', isEqualTo: managerId)
        .where('role', isEqualTo: UserRole.delegate.value)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => AppUser.fromMap(d.data(), d.id))
              .toList();
          list.sort((a, b) => a.name.compareTo(b.name));
          return list;
        });
  }

  Future<void> updateDelegate({
    required AppUser manager,
    required AppUser delegate,
    required String name,
    required String phone,
    required String governorateId,
    required String governorateName,
    required bool isActive,
  }) async {
    await _firestore.collection('users').doc(delegate.uid).update({
      'name': name.trim(),
      'phone': phone.trim(),
      'governorateId': governorateId,
      'governorateName': governorateName,
      'isActive': isActive,
    });
    await AuditHelper.recordLog(
      firestore: _firestore,
      actor: manager,
      actionType: 'update_delegate',
      descriptionAr: 'حدّث المدير بيانات المندوب $name ($governorateName)',
      descriptionEn: 'Manager updated delegate $name ($governorateName)',
      metadata: {'delegateId': delegate.uid, 'isActive': isActive},
    );
  }
}
