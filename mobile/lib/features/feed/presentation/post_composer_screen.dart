import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:companion_ranchi/core/network/api_exception.dart';
import 'package:companion_ranchi/core/theme/app_theme.dart';
import 'package:companion_ranchi/features/feed/application/feed_providers.dart';
import 'package:companion_ranchi/shared/widgets/widgets.dart';

const int _kMaxImages = 10;

/// Companion-only screen to compose a new photo post (multi-image + caption).
class PostComposerScreen extends ConsumerStatefulWidget {
  const PostComposerScreen({super.key});

  @override
  ConsumerState<PostComposerScreen> createState() => _PostComposerScreenState();
}

class _PostComposerScreenState extends ConsumerState<PostComposerScreen> {
  final _picker = ImagePicker();
  final _caption = TextEditingController();
  final List<File> _images = [];

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pickFromGallery() async {
    try {
      final picked = await _picker.pickMultiImage(maxWidth: 1280, imageQuality: 85);
      if (picked.isEmpty) return;
      final remaining = _kMaxImages - _images.length;
      final toAdd = picked.take(remaining < 0 ? 0 : remaining).toList();
      if (toAdd.isNotEmpty) {
        setState(() => _images.addAll(toAdd.map((x) => File(x.path))));
      }
      if (picked.length > toAdd.length && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You can add up to $_kMaxImages photos.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the gallery.')),
        );
      }
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final x = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
        imageQuality: 85,
      );
      if (x == null) return;
      if (_images.length >= _kMaxImages) return;
      setState(() => _images.add(File(x.path)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the camera.')),
        );
      }
    }
  }

  void _showPickSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: AppColors.primary),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickFromGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded, color: AppColors.primary),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickFromCamera();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _publish() async {
    if (_images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one photo to share.')),
      );
      return;
    }
    final post = await ref.read(postComposeControllerProvider.notifier).publish(
          caption: _caption.text,
          images: _images,
        );
    if (!mounted) return;
    if (post != null) {
      invalidateFeeds(ref, companionId: post.companionId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post shared! 🎉')),
      );
      Navigator.of(context).maybePop();
    } else {
      final err = ref.read(postComposeControllerProvider).error;
      final msg = err is ApiException ? err.message : 'Could not share your post. Try again.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final publishing = ref.watch(postComposeControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('New post')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: GradientButton(
            label: 'Share',
            icon: Icons.send_rounded,
            isLoading: publishing,
            onPressed: publishing ? null : _publish,
          ),
        ),
      ),
      body: AbsorbPointer(
        absorbing: publishing,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _PhotoStrip(
              images: _images,
              onAdd: _showPickSheet,
              onRemove: (i) => setState(() => _images.removeAt(i)),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _caption,
              minLines: 3,
              maxLines: 8,
              maxLength: 2000,
              decoration: const InputDecoration(
                hintText: 'Write a caption… keep it friendly and public-place focused.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 15, color: AppColors.inkMuted),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Photos are public. Keep it respectful — no contact details or adult content.',
                    style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal strip of selected photos + an "add" tile.
class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({required this.images, required this.onAdd, required this.onRemove});

  final List<File> images;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (images.length < _kMaxImages)
            GestureDetector(
              onTap: onAdd,
              child: Container(
                width: 100,
                height: 100,
                margin: const EdgeInsets.only(right: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    style: BorderStyle.solid,
                  ),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_rounded, color: AppColors.primary),
                    SizedBox(height: 6),
                    Text('Add', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          for (var i = 0; i < images.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppSpacing.radius),
                    child: Image.file(images[i], width: 100, height: 100, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => onRemove(i),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded, color: Colors.white, size: 15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
