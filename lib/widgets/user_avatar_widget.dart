import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/app_user.dart';

/// عرض الصورة الشخصية للمدير أو المندوب مع دعم Base64 والرابط السحابي وأيقونة افتراضية
class UserAvatarWidget extends StatelessWidget {
  const UserAvatarWidget({
    super.key,
    required this.user,
    this.radius = 20,
    this.backgroundColor,
  });

  final AppUser user;
  final double radius;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final bytes = user.avatarBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        backgroundImage: MemoryImage(bytes),
      );
    }

    final url = user.photoUrl;
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        backgroundImage: CachedNetworkImageProvider(url),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: Icon(
        user.isManager
            ? Icons.admin_panel_settings_outlined
            : Icons.person_outline,
        size: radius * 1.05,
      ),
    );
  }
}
