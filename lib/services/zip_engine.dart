import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

// ============================================================================
// PURE-DART ZIP ENGINE (CENTRAL DIRECTORY UNZIP + CRC32 DEFLATE ZIP + URL DL)
// Zero native dependencies — works on every Flutter / Android version.
// ============================================================================

class ZipExtractResult {
  final Directory targetDir;
  final int fileCount;
  final int totalBytes;
  final bool flattenedSingleRoot;
  final String detectedProjectType; // 'flutter' | 'android' | 'web' | 'generic'
  final String? detectedAppName;
  final String? detectedPackageName;

  const ZipExtractResult({
    required this.targetDir,
    required this.fileCount,
    required this.totalBytes,
    required this.flattenedSingleRoot,
    required this.detectedProjectType,
    this.detectedAppName,
    this.detectedPackageName,
  });
}

class PureZipEngine {
  static final Uint32List _crcTable = _buildCrcTable();

  static Uint32List _buildCrcTable() {
    final table = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      }
      table[n] = c & 0xFFFFFFFF;
    }
    return table;
  }

  static int crc32(List<int> bytes) {
    var c = 0xFFFFFFFF;
    for (var i = 0; i < bytes.length; i++) {
      c = _crcTable[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  static int _u16(Uint8List b, int off) => b[off] | (b[off + 1] << 8);

  static int _u32(Uint8List b, int off) =>
      b[off] | (b[off + 1] << 8) | (b[off + 2] << 16) | (b[off + 3] << 24);

  /// Extracts a ZIP file to [destDir] using the ZIP Central Directory.
  /// Handles both Stored (0) and Deflate (8), data descriptors, and flattens
  /// a single top-level wrapper folder automatically when [flattenSingleRoot] is true.
  static Future<ZipExtractResult> extractZipFile(
    File zipFile,
    Directory destDir, {
    bool flattenSingleRoot = true,
    void Function(int done, int total, String currentFile)? onProgress,
  }) async {
    final bytes = await zipFile.readAsBytes();
    if (bytes.length < 22) {
      throw Exception('ملف ZIP تالف أو فارغ');
    }

    // 1. Locate End of Central Directory (EOCD) signature: 0x06054b50
    final minSearch = math.max(0, bytes.length - 65557);
    var eocdOffset = -1;
    for (var i = bytes.length - 22; i >= minSearch; i--) {
      if (bytes[i] == 0x50 &&
          bytes[i + 1] == 0x4B &&
          bytes[i + 2] == 0x05 &&
          bytes[i + 3] == 0x06) {
        eocdOffset = i;
        break;
      }
    }
    if (eocdOffset < 0) {
      throw Exception('تعذّر العثور على فهرس ZIP — تأكد أن الملف مضغوط بصيغة ZIP صالحة');
    }

    final totalEntries = _u16(bytes, eocdOffset + 10);
    final cdSize = _u32(bytes, eocdOffset + 12);
    final cdOffset = _u32(bytes, eocdOffset + 16);

    if (cdOffset + cdSize > bytes.length) {
      throw Exception('فهرس ملف ZIP غير مكتمل');
    }

    // 2. Parse Central Directory entries
    final entries = <_ZipEntry>[];
    var ptr = cdOffset;
    for (var i = 0; i < totalEntries && ptr + 46 <= bytes.length; i++) {
      if (_u32(bytes, ptr) != 0x02014B50) break;
      final method = _u16(bytes, ptr + 10);
      final compSize = _u32(bytes, ptr + 20);
      final uncompSize = _u32(bytes, ptr + 24);
      final nameLen = _u16(bytes, ptr + 28);
      final extraLen = _u16(bytes, ptr + 30);
      final commentLen = _u16(bytes, ptr + 32);
      final localHeaderOffset = _u32(bytes, ptr + 42);
      final nameBytes = bytes.sublist(ptr + 46, ptr + 46 + nameLen);
      final rawName = utf8.decode(nameBytes, allowMalformed: true);
      ptr += 46 + nameLen + extraLen + commentLen;

      // Skip macOS metadata / system junk
      final norm = rawName.replaceAll('\\', '/');
      if (norm.isEmpty ||
          norm.startsWith('__MACOSX/') ||
          norm.contains('/.DS_Store') ||
          norm == '.DS_Store' ||
          norm.endsWith('/')) {
        continue;
      }
      entries.add(_ZipEntry(
        name: norm,
        method: method,
        compressedSize: compSize,
        uncompressedSize: uncompSize,
        localHeaderOffset: localHeaderOffset,
      ));
    }

    if (entries.isEmpty) {
      throw Exception('لا توجد ملفات داخل الأرشيف المضغوط');
    }

    // 3. Detect if all entries share a single top-level directory
    var stripPrefix = '';
    var flattened = false;
    if (flattenSingleRoot) {
      final firstSegments = <String>{};
      var allHaveSlash = true;
      for (final e in entries) {
        final slash = e.name.indexOf('/');
        if (slash <= 0) {
          allHaveSlash = false;
          break;
        }
        firstSegments.add(e.name.substring(0, slash));
      }
      if (allHaveSlash && firstSegments.length == 1) {
        stripPrefix = '${firstSegments.first}/';
        flattened = true;
      }
    }

    await destDir.create(recursive: true);
    var extractedFiles = 0;
    var extractedBytes = 0;
    final decoder = ZLibDecoder(raw: true);

    // 4. Extract each entry safely
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      var relPath = flattened ? e.name.substring(stripPrefix.length) : e.name;
      // Guard against Zip Slip (../ path traversal)
      relPath = p.normalize(relPath).replaceAll('\\', '/');
      if (relPath.isEmpty ||
          relPath.startsWith('..') ||
          relPath.startsWith('/')) {
        continue;
      }

      final lOff = e.localHeaderOffset;
      if (lOff + 30 > bytes.length || _u32(bytes, lOff) != 0x04034B50) {
        continue;
      }
      final lNameLen = _u16(bytes, lOff + 26);
      final lExtraLen = _u16(bytes, lOff + 28);
      final dataStart = lOff + 30 + lNameLen + lExtraLen;
      final dataEnd = dataStart + e.compressedSize;
      if (dataEnd > bytes.length) continue;

      final compSlice = Uint8List.sublistView(bytes, dataStart, dataEnd);
      List<int> outBytes;
      if (e.method == 0) {
        outBytes = compSlice;
      } else if (e.method == 8) {
        outBytes = decoder.convert(compSlice);
      } else {
        continue; // Unsupported compression method
      }

      final outFile = File(p.join(destDir.path, relPath));
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(outBytes, flush: false);
      extractedFiles++;
      extractedBytes += outBytes.length;

      if (onProgress != null && (i % 5 == 0 || i == entries.length - 1)) {
        onProgress(i + 1, entries.length, relPath);
      }
    }

    // 5. Inspect extracted project type, app name, and package name
    final detected = await inspectProjectDirectory(destDir);
    return ZipExtractResult(
      targetDir: destDir,
      fileCount: extractedFiles,
      totalBytes: extractedBytes,
      flattenedSingleRoot: flattened,
      detectedProjectType: detected.type,
      detectedAppName: detected.appName,
      detectedPackageName: detected.packageName,
    );
  }

  /// Inspects an extracted directory to detect Flutter/Android/Web type, app name, and package ID.
  static Future<({String type, String? appName, String? packageName})>
      inspectProjectDirectory(Directory dir) async {
    var type = 'generic';
    String? appName;
    String? pkgName;

    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (await pubspec.exists()) {
      type = 'flutter';
      try {
        final content = await pubspec.readAsString();
        final m = RegExp(r'^name:\s*([a-zA-Z0-9_]+)', multiLine: true)
            .firstMatch(content);
        if (m != null) appName = m.group(1);
      } catch (_) {}
    }

    final manifest = File(
      p.join(dir.path, 'android', 'app', 'src', 'main', 'AndroidManifest.xml'),
    );
    if (await manifest.exists()) {
      if (type == 'generic') type = 'android';
      try {
        final xml = await manifest.readAsString();
        final labelMatch = RegExp(r'android:label="([^"]+)"').firstMatch(xml);
        if (labelMatch != null &&
            labelMatch.group(1) != null &&
            !labelMatch.group(1)!.startsWith('@')) {
          appName = labelMatch.group(1);
        }
        final pkgMatch = RegExp(r'package="([^"]+)"').firstMatch(xml);
        if (pkgMatch != null) pkgName = pkgMatch.group(1);
      } catch (_) {}
    }

    // Check build.gradle / build.gradle.kts for applicationId
    for (final gradleName in ['build.gradle.kts', 'build.gradle']) {
      final gf = File(p.join(dir.path, 'android', 'app', gradleName));
      if (await gf.exists()) {
        if (type == 'generic') type = 'android';
        try {
          final txt = await gf.readAsString();
          final idMatch = RegExp(
            r'''applicationId\s*=?\s*["']([^"']+)["']''',
          ).firstMatch(txt);
          if (idMatch != null) {
            pkgName = idMatch.group(1);
            break;
          }
        } catch (_) {}
      }
    }

    if (type == 'generic') {
      final idx = File(p.join(dir.path, 'index.html'));
      if (await idx.exists()) type = 'web';
    }

    return (type: type, appName: appName, packageName: pkgName);
  }

  /// Creates a valid ZIP archive from [sourceDir] and writes it to [outputZip].
  static Future<int> zipDirectory(
    Directory sourceDir,
    File outputZip, {
    Set<String> ignoredDirs = const {'.git', 'build', '.dart_tool', '.gradle'},
    void Function(int done, int total)? onProgress,
  }) async {
    final files = <File>[];
    await for (final ent
        in sourceDir.list(recursive: true, followLinks: false)) {
      if (ent is! File) continue;
      final rel = p.relative(ent.path, from: sourceDir.path);
      if (p.split(rel).any((s) => ignoredDirs.contains(s))) continue;
      files.add(ent);
    }

    final out = BytesBuilder(copy: false);
    final centralDir = BytesBuilder(copy: false);
    final encoder = ZLibEncoder(raw: true, level: 6);
    var entryCount = 0;

    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final rel = p.relative(f.path, from: sourceDir.path).replaceAll('\\', '/');
      final nameBytes = utf8.encode(rel);
      final rawBytes = await f.readAsBytes();
      final crc = crc32(rawBytes);

      final compressed = encoder.convert(rawBytes);
      final useDeflate = compressed.length < rawBytes.length;
      final dataBytes = useDeflate ? compressed : rawBytes;
      final method = useDeflate ? 8 : 0;

      final localOffset = out.length;

      // Local File Header (30 bytes)
      final lh = ByteData(30);
      lh.setUint32(0, 0x04034B50, Endian.little);
      lh.setUint16(4, 20, Endian.little); // version needed
      lh.setUint16(6, 0x0800, Endian.little); // UTF-8 flag
      lh.setUint16(8, method, Endian.little);
      lh.setUint16(10, 0, Endian.little);
      lh.setUint16(12, 0, Endian.little);
      lh.setUint32(14, crc, Endian.little);
      lh.setUint32(18, dataBytes.length, Endian.little);
      lh.setUint32(22, rawBytes.length, Endian.little);
      lh.setUint16(26, nameBytes.length, Endian.little);
      lh.setUint16(28, 0, Endian.little);

      out.add(lh.buffer.asUint8List());
      out.add(nameBytes);
      out.add(dataBytes);

      // Central Directory Header (46 bytes)
      final cd = ByteData(46);
      cd.setUint32(0, 0x02014B50, Endian.little);
      cd.setUint16(4, 20, Endian.little);
      cd.setUint16(6, 20, Endian.little);
      cd.setUint16(8, 0x0800, Endian.little);
      cd.setUint16(10, method, Endian.little);
      cd.setUint16(12, 0, Endian.little);
      cd.setUint16(14, 0, Endian.little);
      cd.setUint32(16, crc, Endian.little);
      cd.setUint32(20, dataBytes.length, Endian.little);
      cd.setUint32(24, rawBytes.length, Endian.little);
      cd.setUint16(28, nameBytes.length, Endian.little);
      cd.setUint16(30, 0, Endian.little);
      cd.setUint16(32, 0, Endian.little);
      cd.setUint16(34, 0, Endian.little);
      cd.setUint16(36, 0, Endian.little);
      cd.setUint32(38, 0, Endian.little);
      cd.setUint32(42, localOffset, Endian.little);

      centralDir.add(cd.buffer.asUint8List());
      centralDir.add(nameBytes);
      entryCount++;
      onProgress?.call(i + 1, files.length);
    }

    final cdOffset = out.length;
    final cdBytes = centralDir.takeBytes();
    out.add(cdBytes);

    // End of Central Directory (22 bytes)
    final eocd = ByteData(22);
    eocd.setUint32(0, 0x06054B50, Endian.little);
    eocd.setUint16(4, 0, Endian.little);
    eocd.setUint16(6, 0, Endian.little);
    eocd.setUint16(8, entryCount, Endian.little);
    eocd.setUint16(10, entryCount, Endian.little);
    eocd.setUint32(12, cdBytes.length, Endian.little);
    eocd.setUint32(16, cdOffset, Endian.little);
    eocd.setUint16(20, 0, Endian.little);
    out.add(eocd.buffer.asUint8List());

    await outputZip.parent.create(recursive: true);
    await outputZip.writeAsBytes(out.takeBytes(), flush: true);
    return entryCount;
  }

  /// Downloads a ZIP archive from a direct HTTP/HTTPS URL into [destFile].
  static Future<File> downloadZipFromUrl(
    String url,
    File destFile, {
    void Function(int received, int total)? onProgress,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final req = await client.getUrl(Uri.parse(url.trim()));
      req.headers.set(HttpHeaders.userAgentHeader, 'JOOhub/9.0');
      final res = await req.close();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('فشل التحميل (HTTP ${res.statusCode})');
      }
      final total = res.contentLength;
      await destFile.parent.create(recursive: true);
      final sink = destFile.openWrite();
      var received = 0;
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      return destFile;
    } finally {
      client.close();
    }
  }

  /// Scans common Android folders for .zip files (fallback/quick-pick scanner).
  static Future<List<File>> scanDeviceZipFiles() async {
    final found = <File>[];
    final dirs = <String>[
      if (Platform.isAndroid) '/storage/emulated/0/Download',
      if (Platform.isAndroid) '/storage/emulated/0/Documents',
      if (Platform.isAndroid) '/storage/emulated/0/Documents/JOOhub',
      if (Platform.isAndroid) '/storage/emulated/0/Telegram/Telegram Documents',
    ];
    for (final d in dirs) {
      try {
        final dir = Directory(d);
        if (!await dir.exists()) continue;
        await for (final ent in dir.list(recursive: false, followLinks: false)) {
          if (ent is File && ent.path.toLowerCase().endsWith('.zip')) {
            found.add(ent);
          }
        }
      } catch (_) {}
    }
    found.sort((a, b) {
      try {
        return b.lastModifiedSync().compareTo(a.lastModifiedSync());
      } catch (_) {
        return 0;
      }
    });
    return found;
  }
}

class _ZipEntry {
  final String name;
  final int method;
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;

  _ZipEntry({
    required this.name,
    required this.method,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
  });
}
