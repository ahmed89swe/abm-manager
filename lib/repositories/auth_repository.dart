
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';
import '../models/app_user.dart';
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
    var profile = await fetchUserProfile(uid);

    if (profile == null) {
      final bootstrapRef = _firestore.collection('app_config').doc('bootstrap');
      final bootstrapSnap = await bootstrapRef.get();

      if (!bootstrapSnap.exists) {
        final fallbackName =
            (firebaseUser.displayName?.trim().isNotEmpty ?? false)
            ? firebaseUser.displayName!.trim()
            : email.trim().split('@').first;
        final manager = AppUser(
          uid: uid,
          name: fallbackName,
          email: email.trim(),
          phone: firebaseUser.phoneNumber ?? '',
          role: UserRole.manager,
          isActive: true,
        );

        final batch = _firestore.batch();
        batch.set(_firestore.collection('users').doc(uid), manager.toMap());
        batch.set(bootstrapRef, {
          'managerUid': uid,
          'managerEmail': manager.email,
          'initializedAt': FieldValue.serverTimestamp(),
        });
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
        await _auth.signOut();
        throw StateError(
          'حساب المستخدم غير مسجل في قاعدة البيانات. يجب إنشاء حسابات المندوبين من داخل التطبيق عبر تبويب إدارة المندوبين.',
        );
      }
    }

    if (!profile.isActive) {
      await _auth.signOut();
      throw StateError('تم إيقاف هذا الحساب من قبل المدير.');
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

  /// إنشاء حساب المدير الأول المجهز مسبقاً (يعمل مرة واحدة عند تهيئة النظام)
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
    final user = AppUser(
      uid: cred.user!.uid,
      name: name.trim(),
      email: email.trim(),
      phone: phone.trim(),
      role: UserRole.manager,
      isActive: true,
    );
    final batch = _firestore.batch();
    batch.set(_firestore.collection('users').doc(user.uid), user.toMap());
    batch.set(_firestore.collection('app_config').doc('bootstrap'), {
      'managerUid': user.uid,
      'managerEmail': user.email,
      'initializedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();

    await AuditHelper.recordLog(
      firestore: _firestore,
      actor: user,
      actionType: 'manager_setup',
      descriptionAr: 'تمت تهيئة حساب المدير الأساسي: ${user.name}',
      descriptionEn: 'Primary manager account initialized: ${user.name}',
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

      final delegate = AppUser(
        uid: delegateUid,
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
        titleAr: 'تم إنشاء حساب مندوب جديد',
        titleEn: 'New Delegate Account Created',
        bodyAr: 'تم تسجيل المندوب ${delegate.name} لمحافظة $governorateName',
        bodyEn: 'Delegate ${delegate.name} assigned to $governorateName',
        type: 'delegate_created',
        targetRole: 'delegate',
        audienceTags: ['MANAGERS', 'USER_$delegateUid'],
        targetUserIds: [delegateUid],
        referenceId: delegateUid,
        createdByUid: manager.uid,
      );

      return delegate;
    } finally {
      await secondaryApp?.delete();
    }
  }

  Stream<List<AppUser>> watchAllDelegates() {
    return _firestore
        .collection('users')
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
