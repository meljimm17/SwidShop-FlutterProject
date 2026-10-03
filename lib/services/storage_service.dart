import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../core/constants.dart';

/// Thrown when an upload to Cloudinary fails.
class StorageException implements Exception {
  StorageException(this.message);

  final String message;

  @override
  String toString() => 'StorageException: $message';
}

/// Handles uploading images to Cloudinary using an **unsigned** upload preset.
///
/// Only the returned `secure_url` string is ever persisted to Firestore —
/// never the raw file.
class StorageService {
  StorageService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(seconds: 60),
              ),
            );

  final Dio _dio;

  /// Uploads [file] to the given Cloudinary [folder] using the
  /// `swidshop_uploads` unsigned preset and returns the resulting `secure_url`.
  ///
  /// [folder] must be one of the allowed prefixes:
  /// * [AppConstants.listingsFolder] → `listings/{listingId}`
  /// * [AppConstants.avatarsFolder] → `avatars/{uid}`
  ///
  /// [onProgress] reports 0.0–1.0 as bytes are sent.
  Future<String> uploadImage(
    File file, {
    required String folder,
    ValueChanged<double>? onProgress,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: file.uri.pathSegments.isNotEmpty
              ? file.uri.pathSegments.last
              : 'upload.jpg',
        ),
        'upload_preset': AppConstants.cloudinaryUploadPreset,
        // Unsigned uploads only accept a whitelisted set of params
        // (no `eager`/`transformation`). Resize on-device before upload, or
        // set an incoming transformation on the preset in Cloudinary.
        'folder': folder,
      });

      final response = await _dio.post<Map<String, dynamic>>(
        AppConstants.cloudinaryUploadUrl,
        data: formData,
        onSendProgress: onProgress == null
            ? null
            : (sent, total) {
                if (total > 0) onProgress(sent / total);
              },
      );

      final data = response.data;
      final secureUrl = data?['secure_url'] as String?;
      if (secureUrl == null || secureUrl.isEmpty) {
        throw StorageException('Cloudinary did not return a secure_url.');
      }
      return secureUrl;
    } on DioException catch (e) {
      final data = e.response?.data;
      String? detail;
      if (data is Map) {
        final error = data['error'];
        if (error is Map) detail = error['message']?.toString();
      }
      throw StorageException(
        detail ?? e.message ?? 'Upload failed. Check your connection.',
      );
    } catch (e) {
      if (e is StorageException) rethrow;
      throw StorageException('Unexpected upload error: $e');
    }
  }

  /// Re-encodes [file] as JPEG at [quality]% with its longest edge capped at
  /// [maxEdge]px (EXIF rotation applied). Camera photos typically shrink from
  /// several MB to a few hundred KB. Falls back to the original file if
  /// compression fails.
  static Future<File> compressForUpload(
    File file, {
    int maxEdge = 1600,
    int quality = 80,
  }) async {
    try {
      final bytes = await file.readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final w = descriptor.width;
      final h = descriptor.height;
      descriptor.dispose();
      buffer.dispose();

      final longest = w > h ? w : h;
      final shortest = w > h ? h : w;
      final scale = longest > maxEdge ? maxEdge / longest : 1.0;
      // The plugin scales by max(minWidth/w, minHeight/h). Passing the scaled
      // *short* edge for both makes that factor exactly [scale] whether or
      // not EXIF rotation swaps width and height.
      final minSide = (shortest * scale).round();
      final target =
          '${Directory.systemTemp.path}/swid_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final out = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        target,
        minWidth: minSide,
        minHeight: minSide,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      return out == null ? file : File(out.path);
    } catch (e) {
      debugPrint('compressForUpload failed, using original: $e');
      return file;
    }
  }

  /// Convenience: upload an item photo for [listingId].
  Future<String> uploadListingImage(
    File file,
    String listingId, {
    ValueChanged<double>? onProgress,
  }) =>
      uploadImage(
        file,
        folder: AppConstants.listingsFolder(listingId),
        onProgress: onProgress,
      );

  /// Convenience: upload a profile photo for [uid].
  Future<String> uploadAvatar(File file, String uid) =>
      uploadImage(file, folder: AppConstants.avatarsFolder(uid));

  /// Uploads several images sequentially (keeps ordering deterministic).
  Future<List<String>> uploadImages(
    List<File> files, {
    required String folder,
    ValueChanged<int>? onProgress,
  }) async {
    final urls = <String>[];
    for (var i = 0; i < files.length; i++) {
      urls.add(await uploadImage(files[i], folder: folder));
      onProgress?.call(i + 1);
    }
    return urls;
  }
}
