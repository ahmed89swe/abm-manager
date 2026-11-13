import 'dart:convert';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

/// بيانات صورة مختارة متوافقة بالكامل مع الويب والأندرويد دون الاعتماد على dart:io
class PickedImageData {
  const PickedImageData({
    required this.bytes,
    required this.fileName,
  });

  final Uint8List bytes;
  final String fileName;
}

class ReceiptStorageService {
  ReceiptStorageService._();
  static final ReceiptStorageService instance = ReceiptStorageService._();

  final ImagePicker _picker = ImagePicker();

  Future<PickedImageData?> pickImage({required ImageSource source}) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 68,
      maxWidth: 1024,
    );
    if (picked == null) return null;
    final rawBytes = await picked.readAsBytes();
    final compressed = await _compressBytes(
      rawBytes,
      minWidth: 960,
      minHeight: 960,
      quality: 65,
    );
    return PickedImageData(
      bytes: compressed,
      fileName: picked.name.isNotEmpty
          ? picked.name
          : 'receipt_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
  }

  /// التقاط/اختيار صورة شخصية وضغطها وتحويلها لبايتات/Base64 مضغوطة لتعمل فوراً على كل المنصات
  Future<({PickedImageData image, String base64})?> pickAvatar({
    required ImageSource source,
  }) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 72,
      maxWidth: 400,
      maxHeight: 400,
    );
    if (picked == null) return null;
    final rawBytes = await picked.readAsBytes();
    final compressedBytes = await _compressBytes(
      rawBytes,
      minWidth: 256,
      minHeight: 256,
      quality: 68,
    );
    final image = PickedImageData(
      bytes: compressedBytes,
      fileName: picked.name.isNotEmpty
          ? picked.name
          : 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    return (image: image, base64: base64Encode(compressedBytes));
  }

  Future<Uint8List> _compressBytes(
    Uint8List bytes, {
    required int minWidth,
    required int minHeight,
    required int quality,
  }) async {
    if (kIsWeb) {
      // ImagePicker في الويب يطبق maxWidth/maxHeight و imageQuality مسبقاً
      return bytes;
    }
    try {
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: minWidth,
        minHeight: minHeight,
        quality: quality,
      );
      if (result.isNotEmpty) {
        return result;
      }
    } catch (e) {
      debugPrint('Image compression fallback: $e');
    }
    return bytes;
  }

  /// رفع صورة الوصل إلى Firebase Storage مع دعم الويب والموبايل عبر putData
  Future<String?> uploadReceipt({
    required PickedImageData image,
    required String folder,
    required String referenceId,
  }) async {
    try {
      final fileName =
          '${referenceId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance.ref().child('$folder/$fileName');
      final task = await ref
          .putData(
            image.bytes,
            SettableMetadata(contentType: 'image/jpeg'),
          )
          .timeout(const Duration(seconds: 6));
      return await task.ref.getDownloadURL().timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('Storage upload fallback: $e');
      // إذا لم يكن Firebase Storage مفعّلاً أو تعذّر الرفع نحفظ صورة مصغرة Data URI إن كانت ضمن حدود وثيقة Firestore
      if (image.bytes.lengthInBytes <= 450 * 1024) {
        return 'data:image/jpeg;base64,${base64Encode(image.bytes)}';
      }
      return null;
    }
  }
}
