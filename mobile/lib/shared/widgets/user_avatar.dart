import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/shared/widgets/online_dot.dart';

/// Circular avatar with a network photo, initials fallback, and optional online
/// presence dot.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    this.photoUrl,
    this.name,
    this.radius = 22,
    this.isOnline,
    this.light = false,
  });

  final String? photoUrl;
  final String? name;
  final double radius;

  /// When non-null, shows a presence dot overlay.
  final bool? isOnline;

  /// Renders the initials fallback as white on a translucent-white circle so it
  /// stays legible on top of the brand gradient (e.g. the profile header).
  final bool light;

  String get _initials {
    final n = (name ?? '').trim();
    if (n.isEmpty) return '?';
    final parts = n.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    // Decode the photo at the avatar's actual pixel size, not its native
    // resolution. A 44px avatar decoding a 1080px portrait wastes memory and
    // stutters on scroll (avatars appear in every list/tile/chat bubble).
    final int decodePx =
        (radius * 2 * MediaQuery.devicePixelRatioOf(context)).round();

    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: light
          ? Colors.white.withValues(alpha: 0.22)
          : AppColors.primary.withValues(alpha: 0.15),
      child: ClipOval(
        child: (photoUrl != null && photoUrl!.isNotEmpty)
            ? CachedNetworkImage(
                imageUrl: photoUrl!,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                memCacheWidth: decodePx,
                memCacheHeight: decodePx,
                errorWidget: (_, __, ___) => _initialsWidget(),
                placeholder: (_, __) => _initialsWidget(),
              )
            : _initialsWidget(),
      ),
    );

    if (isOnline == null) return avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: 0,
          bottom: 0,
          child: OnlineDot(isOnline: isOnline!, size: radius * 0.36),
        ),
      ],
    );
  }

  Widget _initialsWidget() {
    return Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      color: light
          ? Colors.white.withValues(alpha: 0.22)
          : AppColors.primary.withValues(alpha: 0.15),
      child: Text(
        _initials,
        style: TextStyle(
          color: light ? Colors.white : AppColors.primary,
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}
