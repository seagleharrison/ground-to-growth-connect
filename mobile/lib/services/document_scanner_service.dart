import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:image_picker/image_picker.dart';

/// One page of a document, ready to upload.
class ScannedPage {
  final List<int> bytes;
  final String mimeType;
  ScannedPage(this.bytes, this.mimeType);
}

/// Two ways to get a document into the app: the camera scanner
/// (cunning_document_scanner — VisionKit on iOS, ML Kit on Android, the
/// cross-platform equivalent of the native app's DocumentScanner.swift) or
/// picking existing photos from the library.
class DocumentScannerService {
  DocumentScannerService._();

  /// Returns each scanned page, in order. Empty if the user cancels.
  static Future<List<ScannedPage>> scan() async {
    final paths = await CunningDocumentScanner.getPictures(noOfPages: 5) ?? [];
    final pages = <ScannedPage>[];
    for (final path in paths) {
      pages.add(ScannedPage(await File(path).readAsBytes(), 'image/jpeg'));
    }
    return pages;
  }

  /// Lets the user pick one or more existing photos. Empty if cancelled.
  static Future<List<ScannedPage>> pickFromPhotos() async {
    final picked = await ImagePicker().pickMultiImage(imageQuality: 85, maxWidth: 2400);
    final pages = <ScannedPage>[];
    for (final file in picked) {
      final bytes = await file.readAsBytes();
      pages.add(ScannedPage(bytes, mimeTypeFor(bytes)));
    }
    return pages;
  }

  /// PNG files start with the bytes 89 50 4E 47; anything else the picker
  /// hands back has been re-encoded as JPEG.
  static String mimeTypeFor(List<int> bytes) {
    final isPng = bytes.length > 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    return isPng ? 'image/png' : 'image/jpeg';
  }
}
