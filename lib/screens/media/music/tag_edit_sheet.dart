import 'package:local_library/design_tokens/app_radius.dart';
import 'package:local_library/design_tokens/app_colors.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../models/song.dart';
import '../../../services/metadata_service.dart';
import '../../../database/song_dao.dart';
import '../../../services/music_player_service.dart';
import 'music_library_view.dart';

class TagEditSheet extends StatefulWidget {
  final Song song;

  const TagEditSheet({super.key, required this.song});

  @override
  State<TagEditSheet> createState() => _TagEditSheetState();
}

class _TagEditSheetState extends State<TagEditSheet> {
  final _titleController = TextEditingController();
  final _artistController = TextEditingController();
  final _albumController = TextEditingController();
  final _dao = SongDao();
  bool _isSaving = false;
  String? _newCoverPath;
  Uint8List? _newCoverBytes;

  @override
  void initState() {
    super.initState();
    _titleController.text = widget.song.title ?? '';
    _artistController.text = widget.song.artist ?? '';
    _albumController.text = widget.song.album ?? '';
    _newCoverPath = widget.song.coverPath;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    final bytes = await image.readAsBytes();
    setState(() {
      _newCoverBytes = bytes;
      _newCoverPath = image.path;
    });
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final title = _titleController.text.trim().isEmpty ? null : _titleController.text.trim();
      final artist = _artistController.text.trim().isEmpty ? null : _artistController.text.trim();
      final album = _albumController.text.trim().isEmpty ? null : _albumController.text.trim();

      // 1. 写入音频文件标签
      await MetadataService.instance.writeMetadata(
        filePath: widget.song.filePath,
        title: title,
        artist: artist,
        album: album,
        coverBytes: _newCoverBytes,
      );

      // 2. 如果有新封面，保存到本地缓存
      String? coverPath = widget.song.coverPath;
      if (_newCoverBytes != null) {
        coverPath = await MetadataService.instance.saveCoverImage(
          _newCoverBytes!,
          widget.song.filePath,
        );
      }

      // 3. 更新数据库
      final updatedSong = widget.song.copyWith(
        title: title,
        artist: artist,
        album: album,
        coverPath: coverPath,
      );
      await _dao.updateSongMetadata(updatedSong);

      // 4. 更新播放队列中的歌曲信息
      MusicPlayerService.instance.updateSongInQueue(updatedSong);

      // 5. 刷新音乐库
      MusicLibraryView.globalKey.currentState?.refresh();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('标签已保存'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            backgroundColor: NeutralColorsDark.surfaceElevated,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: NeutralColorsDark.surfaceElevated,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = neutral.surface;
    final textColor = neutral.textPrimary;
    final fieldBg = isDark ? neutral.surfaceElevated : neutral.background;
    final subTextColor = neutral.textSecondary;
    final handleColor = neutral.textTertiary;

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
      ),
      child: Column(
        children: [
          // 顶部把手
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: handleColor,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '编辑标签',
            style: TextStyle(
              color: textColor,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          // 封面区域
          GestureDetector(
            onTap: _pickCover,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: fieldBg,
                borderRadius: BorderRadius.circular(AppRadius.medium),
              ),
              child: _buildCover(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击更换封面',
            style: TextStyle(fontSize: 12, color: subTextColor),
          ),
          const SizedBox(height: 20),
          // 表单
          Expanded(
            child: ListView(
              cacheExtent: 200.0,
              padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomPadding),
              children: [
                _buildTextField('歌曲标题', _titleController, fieldBg: fieldBg, textColor: textColor, subTextColor: subTextColor),
                const SizedBox(height: 16),
                _buildTextField('艺术家', _artistController, fieldBg: fieldBg, textColor: textColor, subTextColor: subTextColor),
                const SizedBox(height: 16),
                _buildTextField('专辑', _albumController, fieldBg: fieldBg, textColor: textColor, subTextColor: subTextColor),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppRadius.small),
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const CupertinoActivityIndicator(color: Colors.white)
                        : const Text('保存', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCover() {
    final neutral = NeutralPalette.of(context);
    if (_newCoverBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: Image.memory(_newCoverBytes!, fit: BoxFit.cover),
      );
    }
    if (_newCoverPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: Image.file(
          File(_newCoverPath!),
          fit: BoxFit.cover,
          cacheWidth: 400,
          errorBuilder: (_, __, ___) => Center(
            child: Icon(CupertinoIcons.photo, color: neutral.textTertiary, size: 40),
          ),
        ),
      );
    }
    return Center(
      child: Icon(CupertinoIcons.photo, color: neutral.textTertiary, size: 40),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {required Color fieldBg, required Color textColor, required Color subTextColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: subTextColor,
          ),
        ),
        const SizedBox(height: 8),
        CupertinoTextField(
          controller: controller,
          style: TextStyle(color: textColor, fontSize: 16),
          decoration: BoxDecoration(
            color: fieldBg,
            borderRadius: BorderRadius.circular(AppRadius.small),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
      ],
    );
  }
}
