import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import 'platform_target.dart';

/// 文本文件的保存 / 选择。
///
/// file_picker 没有鸿蒙实现，所以在鸿蒙上改走 `duanju/device` 通道，
/// 由 ArkTS 的 DeviceChannel 调系统文件选择器（保存、打开各一套）。
/// 其余平台保持原来的 file_picker 行为。
class PlatformFiles {
  static const _channel = MethodChannel('duanju/device');

  /// 让用户选位置保存一份 UTF-8 文本；用户取消返回 false。
  static Future<bool> saveText(
    String name,
    String content, {
    String mimeType = 'application/json',
  }) async {
    if (isOhos) {
      final saved = await _channel.invokeMethod<bool>('saveTextFile', {
        'name': name,
        'mimeType': mimeType,
        'content': content,
      });
      return saved ?? false;
    }
    final path = await FilePicker.saveFile(
      fileName: name,
      bytes: Uint8List.fromList(utf8.encode(content)),
      mimeType: mimeType,
    );
    return path != null;
  }

  /// 让用户挑一个文本文件读出来；用户取消返回 null。
  static Future<String?> pickText({
    List<String> allowedExtensions = const ['json'],
  }) async {
    if (isOhos) {
      try {
        return await _channel.invokeMethod<String>('pickTextFile', {
          'extensions': allowedExtensions.join(','),
        });
      } on PlatformException catch (error) {
        if (error.code == 'too_large') {
          throw const FormatException('备份文件过大或无法读取');
        }
        rethrow;
      }
    }
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    if (file == null) return null;
    final size = await file.length();
    if (size == null || size > 8 * 1024 * 1024) {
      throw const FormatException('备份文件过大或无法读取');
    }
    return utf8.decode(await file.readAsBytes());
  }
}
