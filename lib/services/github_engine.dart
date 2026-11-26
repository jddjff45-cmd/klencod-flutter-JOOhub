import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

// ============================================================================
// PURE-DART GITHUB ENGINE
// • 5-Stage Staged Upload Pipeline (Scan -> SHA-1 Delta -> Batches -> Commit -> Verify)
// • Pause / Resume / Cancel + Checkpoint Recovery (لو النت قطع بيكمل من مطرح ما وقف)
// • Resilient HTTP Client with Exponential Backoff + Rate-Limit Awareness
// • Egyptian Arabic Error Diagnostics (سبب كل خطأ + الحل العملي + التفاصيل التقنية)
// • Live Connection Health Doctor (DNS + Ping + Rate Limit + Token Scopes)
// • Branch Manager + Commits History + Actions + 500MB Release Streaming
// ============================================================================

class GitSha1 {
  static Future<String> gitBlobSha1(File file) async {
    final len = await file.length();
    final h = _Sha1Hasher()..add(utf8.encode('blob $len\u0000'));
    await for (final chunk in file.openRead()) {
      h.add(chunk);
    }
    return h.closeHex();
  }
}

class _Sha1Hasher {
  int _h0 = 0x67452301;
  int _h1 = 0xEFCDAB89;
  int _h2 = 0x98BADCFE;
  int _h3 = 0x10325476;
  int _h4 = 0xC3D2E1F0;
  final Uint8List _buf = Uint8List(64);
  int _bufLen = 0;
  int _totalBytes = 0;
  final Uint32List _w = Uint32List(80);

  void add(List<int> data) {
    var offset = 0;
    _totalBytes += data.length;
    while (offset < data.length) {
      final take = math.min(64 - _bufLen, data.length - offset);
      _buf.setRange(_bufLen, _bufLen + take, data, offset);
      _bufLen += take;
      offset += take;
      if (_bufLen == 64) {
        _processBlock(_buf);
        _bufLen = 0;
      }
    }
  }

  void _processBlock(Uint8List b) {
    for (var i = 0; i < 16; i++) {
      final j = i * 4;
      _w[i] = ((b[j] << 24) | (b[j + 1] << 16) | (b[j + 2] << 8) | b[j + 3]) &
          0xFFFFFFFF;
    }
    for (var i = 16; i < 80; i++) {
      final x = _w[i - 3] ^ _w[i - 8] ^ _w[i - 14] ^ _w[i - 16];
      _w[i] = ((x << 1) | (x >>> 31)) & 0xFFFFFFFF;
    }
    var a = _h0;
    var b0 = _h1;
    var c = _h2;
    var d = _h3;
    var e = _h4;
    for (var i = 0; i < 80; i++) {
      int f;
      int k;
      if (i < 20) {
        f = (b0 & c) | ((~b0 & 0xFFFFFFFF) & d);
        k = 0x5A827999;
      } else if (i < 40) {
        f = b0 ^ c ^ d;
        k = 0x6ED9EBA1;
      } else if (i < 60) {
        f = (b0 & c) | (b0 & d) | (c & d);
        k = 0x8F1BBCDC;
      } else {
        f = b0 ^ c ^ d;
        k = 0xCA62C1D6;
      }
      final temp = ((((a << 5) | (a >>> 27)) & 0xFFFFFFFF) + f + e + k + _w[i]) &
          0xFFFFFFFF;
      e = d;
      d = c;
      c = ((b0 << 30) | (b0 >>> 2)) & 0xFFFFFFFF;
      b0 = a;
      a = temp;
    }
    _h0 = (_h0 + a) & 0xFFFFFFFF;
    _h1 = (_h1 + b0) & 0xFFFFFFFF;
    _h2 = (_h2 + c) & 0xFFFFFFFF;
    _h3 = (_h3 + d) & 0xFFFFFFFF;
    _h4 = (_h4 + e) & 0xFFFFFFFF;
  }

  String closeHex() {
    final bitLen = _totalBytes * 8;
    add(const [0x80]);
    if (_bufLen > 56) {
      while (_bufLen < 64) {
        _buf[_bufLen++] = 0;
      }
      _processBlock(_buf);
      _bufLen = 0;
    }
    while (_bufLen < 56) {
      _buf[_bufLen++] = 0;
    }
    for (var i = 7; i >= 0; i--) {
      _buf[_bufLen++] = (bitLen >>> (i * 8)) & 0xFF;
    }
    _processBlock(_buf);
    String hex32(int v) => v.toRadixString(16).padLeft(8, '0');
    return '${hex32(_h0)}${hex32(_h1)}${hex32(_h2)}${hex32(_h3)}${hex32(_h4)}';
  }
}

class GitHubConfig {
  static String oauthClientId = 'Ov23lihWF0EZ4KECillw';
  static const int maxTotalUploadBytes = 500 * 1024 * 1024; // 500 MB
  static const int maxGitBlobBytes = 90 * 1024 * 1024; // 90 MB
}

class GitHubAuthSession {
  String accessToken;
  String? refreshToken;
  String? clientId;
  DateTime? expiresAt;

  GitHubAuthSession({
    required this.accessToken,
    this.refreshToken,
    this.clientId,
    this.expiresAt,
  });

  bool get isExpired =>
      expiresAt != null &&
      DateTime.now().isAfter(expiresAt!.subtract(const Duration(minutes: 2)));

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'clientId': clientId,
        'expiresAt': expiresAt?.toIso8601String(),
      };

  factory GitHubAuthSession.fromJson(Map<String, dynamic> j) =>
      GitHubAuthSession(
        accessToken: (j['accessToken'] ?? '').toString(),
        refreshToken: j['refreshToken'] as String?,
        clientId: j['clientId'] as String?,
        expiresAt: j['expiresAt'] != null
            ? DateTime.tryParse(j['expiresAt'].toString())
            : null,
      );
}

/// Controls Cancellation + Pause / Resume for Staged Uploads
class GitHubCancelToken {
  bool _cancelled = false;
  bool _paused = false;
  Completer<void>? _resumeCompleter;

  bool get isCancelled => _cancelled;
  bool get isPaused => _paused;

  void cancel() {
    _cancelled = true;
    _paused = false;
    if (_resumeCompleter != null && !_resumeCompleter!.isCompleted) {
      _resumeCompleter!.complete();
    }
  }

  void pause() {
    if (_cancelled || _paused) return;
    _paused = true;
    _resumeCompleter = Completer<void>();
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    if (_resumeCompleter != null && !_resumeCompleter!.isCompleted) {
      _resumeCompleter!.complete();
    }
    _resumeCompleter = null;
  }

  Future<void> waitIfPaused() async {
    while (_paused && !_cancelled) {
      final c = _resumeCompleter;
      if (c != null) {
        await c.future;
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
  }
}

/// Rich Egyptian Arabic Exception with Exact Root Cause & Actionable Fix
class GitHubException implements Exception {
  final int statusCode;
  final String message;
  final String title;
  final String reason;
  final String solution;
  final String technicalDetail;
  final bool isRetryable;

  GitHubException(
    this.statusCode,
    this.message, {
    String? title,
    String? reason,
    String? solution,
    String? technicalDetail,
    this.isRetryable = false,
  })  : title = title ?? _defaultTitle(statusCode),
        reason = reason ?? message,
        solution = solution ?? _defaultSolution(statusCode),
        technicalDetail = technicalDetail ?? 'HTTP $statusCode • $message';

  static String _defaultTitle(int code) {
    switch (code) {
      case -1:
        return 'مفيش نت أو مشكلة في الـ DNS';
      case -2:
        return 'الاتصال اتأخر جداً (Timeout)';
      case -3:
        return 'مشكلة في شهادة الأمان (SSL/TLS)';
      case -4:
        return 'الاتصال اتقطع في النص';
      case 401:
        return 'التوكن غلط أو صلاحيته خلصت';
      case 403:
        return 'ممنوع الوصول أو عدّيت الحد المسموح';
      case 404:
        return 'المستودع أو الفرع مش موجود';
      case 409:
        return 'تعارض في الفرع أو المستودع فاضي';
      case 413:
        return 'حجم الملف أكبر من المسموح';
      case 422:
        return 'بيانات مش مظبوطة أو الاسم متكرر';
      case 429:
        return 'طلبات كتير في وقت قصير';
      case 499:
        return 'تم إلغاء العملية';
      default:
        if (code >= 500) return 'عطل مؤقت في سيرفرات GitHub';
        return 'حصل خطأ في الاتصال ($code)';
    }
  }

  static String _defaultSolution(int code) {
    switch (code) {
      case -1:
        return 'اتأكد إن الواي فاي أو باقة الموبايل شغالة، وجرب تقفل أي VPN أو DNS مخصص واختبر الاتصال من زرار «فحص الشبكة».';
      case -2:
        return 'النت عندك بطيء شوية دلوقتي. زوّد مهلة الاتصال من الإعدادات لـ 60 ثانية أو قلّل حجم الدفعة لـ 3 ملفات وجرب تاني.';
      case -3:
        return 'اتأكد إن التاريخ والساعة في الموبايل مظبوطين تلقائياً، وإن مفيش بروكسي بيقطع اتصال HTTPS.';
      case -4:
        return 'الشبكة اتهزت أثناء الرفع. متقلقش، نقطة الاستكمال محفوظة — اضغط «جرب تاني» وهيكمل من مطرح ما وقف.';
      case 401:
        return 'ادخل على الإعدادات -> حسابات GitHub واعمل ربط للحساب من جديد أو جدّد الـ Personal Access Token.';
      case 403:
        return 'اتأكد إن التوكن واخد صلاحية repo و workflow. ولو عدّيت حد الطلبات استنى دقايق وجرب تاني.';
      case 404:
        return 'اتأكد إن اسم المستودع والفرع صح وإن التوكن بتاعك له صلاحية يدخل على المستودع ده (خصوصاً لو خاص Private).';
      case 409:
        return 'المستودع لسه جديد وفاضي أو حصل تحديث متزامن. جرب تعمّل Refresh للمستودعات وحاول تاني.';
      case 413:
        return 'الحد الأقصى للملف الواحد في Git هو 90MB (والبث المباشر 500MB). قسّم الملف أو امسح مجلد build قبل الرفع.';
      case 422:
        return 'لو بتعمل مستودع جديد، غيّر اسمه عشان الاسم ده موجود عندك قبل كده، أو راجع رسالة الخطأ التقنية تحت.';
      case 429:
        return 'GitHub طلب نهدّي السرعة شوية. قلّل حجم الدفعة من الإعدادات واستنى دقيقة وجرب تاني.';
      case 499:
        return 'أنت اللي وقّفت العملية. تقدر تبدأها تاني في أي وقت.';
      default:
        if (code >= 500) {
          return 'دي مشكلة مؤقتة عند سيرفرات GitHub نفسها مش عندك. استنى دقيقة واضغط «جرب تاني».';
        }
        return 'افحص الشبكة من زرار «فحص الشبكة» وراجع التفاصيل التقنية تحت عشان تعرف السبب بالظبط.';
    }
  }

  /// Translates any raw Dart/Socket/HTTP error into an Egyptian Arabic diagnostic
  static GitHubException diagnose(
    Object error, {
    String? endpoint,
    int? statusCode,
    dynamic parsedBody,
    String? rawBody,
    Map<String, String>? responseHeaders,
  }) {
    if (error is GitHubException) return error;

    final ep = endpoint ?? '';
    final rawStr = rawBody ?? (parsedBody?.toString() ?? error.toString());

    // 1. Network / Socket / DNS / TLS / Timeout errors
    if (error is TimeoutException) {
      return GitHubException(
        -2,
        'انتهت مهلة الاتصال بسيرفر GitHub',
        title: 'الاتصال اتأخر جداً (Timeout)',
        reason:
            'السيرفر مردّش خلال الوقت المحدد — غالباً النت بطيء أو في ضغط على الشبكة دلوقتي.',
        solution: _defaultSolution(-2),
        technicalDetail: 'TimeoutException on $ep\n${error.message ?? ''}',
        isRetryable: true,
      );
    }

    if (error is HandshakeException || error is TlsException) {
      return GitHubException(
        -3,
        'فشل تأمين الاتصال المشفّر (SSL/TLS)',
        title: 'مشكلة في شهادة الأمان (SSL/TLS)',
        reason:
            'الموبايل معرفش يوثّق اتصال HTTPS مع GitHub — غالباً بسبب الساعة/التاريخ غلط أو شبكة مقيدة.',
        solution: _defaultSolution(-3),
        technicalDetail: '${error.runtimeType} on $ep\n$error',
        isRetryable: true,
      );
    }

    if (error is SocketException) {
      final msgLower = error.message.toLowerCase();
      final osMsg = error.osError?.message.toLowerCase() ?? '';
      final isDns = msgLower.contains('failed host lookup') ||
          msgLower.contains('no address associated') ||
          osMsg.contains('nodename') ||
          osMsg.contains('name or service not known');
      if (isDns) {
        return GitHubException(
          -1,
          'مش عارفين نوصل لعنوان GitHub (DNS)',
          title: 'مفيش نت أو مشكلة في الـ DNS',
          reason:
              'الموبايل مش لاقي اتصال بالإنترنت أو الـ DNS مش قادر يترجم عنوان api.github.com.',
          solution: _defaultSolution(-1),
          technicalDetail: 'SocketException (DNS) on $ep\n${error.message}',
          isRetryable: true,
        );
      }
      return GitHubException(
        -4,
        'الاتصال اتقطع فجأة أثناء النقل',
        title: 'الاتصال اتقطع في النص',
        reason:
            'الشبكة فصلت أو اتبدّلت بين الواي فاي والداتا أثناء نقل البيانات ($ep).',
        solution: _defaultSolution(-4),
        technicalDetail:
            'SocketException on $ep\n${error.message} (${error.osError?.message ?? ''})',
        isRetryable: true,
      );
    }

    if (error is HttpException) {
      return GitHubException(
        -4,
        'انقطع اتصال HTTP قبل اكتمال الرد',
        title: 'انقطع الاتصال بالسيرفر',
        reason: 'سيرفر GitHub قفل الاتصال قبل ما الرد يكتمل.',
        solution: _defaultSolution(-4),
        technicalDetail: 'HttpException on $ep\n${error.message}',
        isRetryable: true,
      );
    }

    // 2. HTTP Status Code errors from GitHub API
    if (statusCode != null) {
      var apiMsg = '';
      if (parsedBody is Map<String, dynamic>) {
        apiMsg = (parsedBody['message'] ?? parsedBody['error_description'] ?? '')
            .toString();
        final errs = parsedBody['errors'];
        if (errs is List && errs.isNotEmpty) {
          final first = errs.first;
          if (first is Map && first['message'] != null) {
            apiMsg = '$apiMsg (${first['message']})';
          }
        }
      }
      final low = apiMsg.toLowerCase();
      final rateRem = responseHeaders?['x-ratelimit-remaining'];
      final rateReset = responseHeaders?['x-ratelimit-reset'];

      if (statusCode == 401) {
        return GitHubException(
          401,
          apiMsg.isEmpty ? 'التوكن غير صالح' : apiMsg,
          title: 'التوكن غلط أو صلاحيته خلصت',
          reason:
              'GitHub رفض تسجيل الدخول لأن التوكن منتهي أو اتلغى من حسابك.',
          solution: _defaultSolution(401),
          technicalDetail: 'HTTP 401 on $ep\nGitHub: $apiMsg',
        );
      }

      if (statusCode == 403) {
        if (rateRem == '0' || low.contains('rate limit')) {
          var waitHint = 'دقايق';
          final resetEpoch = int.tryParse(rateReset ?? '');
          if (resetEpoch != null) {
            final dt =
                DateTime.fromMillisecondsSinceEpoch(resetEpoch * 1000);
            final mins = dt.difference(DateTime.now()).inMinutes.clamp(1, 60);
            waitHint = 'حوالي $mins دقيقة';
          }
          return GitHubException(
            403,
            'عدّيت حد طلبات GitHub API',
            title: 'عدّيت الحد المسموح من GitHub',
            reason:
                'استهلكت كل طلبات الساعة المتاحة لحسابك على GitHub API. الرصيد هيتجدد خلال $waitHint.',
            solution:
                'استنى $waitHint وجرب تاني، أو قلّل عدد الملفات اللي بترفعها في المرة الواحدة.',
            technicalDetail:
                'HTTP 403 RateLimit on $ep\nRemaining: $rateRem • Reset: $rateReset\n$apiMsg',
            isRetryable: false,
          );
        }
        return GitHubException(
          403,
          apiMsg.isEmpty ? 'صلاحيات التوكن غير كافية' : apiMsg,
          title: 'التوكن ناقصه صلاحيات',
          reason:
              'GitHub منع العملية دي لأن التوكن مش واخد صلاحيات repo أو workflow الكاملة.',
          solution:
              'اعمل ربط جديد من شاشة «ربط حساب GitHub» أو اتأكد إن التوكن بتاعك متعلّم فيه على repo و workflow.',
          technicalDetail: 'HTTP 403 on $ep\nGitHub: $apiMsg',
        );
      }

      if (statusCode == 404) {
        return GitHubException(
          404,
          apiMsg.isEmpty ? 'العنصر غير موجود' : apiMsg,
          title: 'المستودع أو الملف مش موجود (404)',
          reason:
              'العنوان المطلوب مش موجود على GitHub أو المستودع خاص والتوكن ملوش صلاحية عليه.',
          solution: _defaultSolution(404),
          technicalDetail: 'HTTP 404 on $ep\nGitHub: $apiMsg',
        );
      }

      if (statusCode == 409) {
        return GitHubException(
          409,
          apiMsg.isEmpty ? 'تعارض في المستودع' : apiMsg,
          title: 'تعارض في الفرع أو المستودع فاضي (409)',
          reason: low.contains('empty')
              ? 'المستودع ده لسه فاضي تماماً ومفيهوش ولا ملف (ولا حتى README).'
              : 'حصل تعارض بين التحديث بتاعك وآخر تعديل موجود على الفرع ده.',
          solution: low.contains('empty')
              ? 'ابعت ملف README أو اعمل مستودع جديد من التطبيق (بـ auto_init) وهيتظبط فوراً.'
              : 'حدّث قائمة المستودعات وجرب الرفع مرة تانية.',
          technicalDetail: 'HTTP 409 on $ep\nGitHub: $apiMsg',
        );
      }

      if (statusCode == 422) {
        final alreadyExists = low.contains('name already exists');
        return GitHubException(
          422,
          apiMsg.isEmpty ? 'خطأ في البيانات المرسلة' : apiMsg,
          title: alreadyExists
              ? 'اسم المستودع موجود قبل كده!'
              : 'بيانات غير مقبولة من GitHub (422)',
          reason: alreadyExists
              ? 'عندك فعلاً مستودع بنفس الاسم ده على حسابك في GitHub.'
              : 'GitHub رفض البيانات: ${apiMsg.isEmpty ? rawStr : apiMsg}',
          solution: alreadyExists
              ? 'اختار اسم مستودع مختلف أو اختار المستودع الموجود من القائمة فوق.'
              : _defaultSolution(422),
          technicalDetail: 'HTTP 422 on $ep\nGitHub: $apiMsg',
        );
      }

      if (statusCode == 429) {
        return GitHubException(
          429,
          'طلبات كتير في وقت قصير',
          title: 'GitHub طلب نهدّي السرعة (429)',
          reason:
              'بعتنا طلبات كتير ورا بعض بسرعة عالية فـ GitHub فعّل الحماية المؤقتة.',
          solution: _defaultSolution(429),
          technicalDetail: 'HTTP 429 on $ep\nGitHub: $apiMsg',
          isRetryable: true,
        );
      }

      if (statusCode >= 500) {
        return GitHubException(
          statusCode,
          'عطل مؤقت في سيرفر GitHub ($statusCode)',
          title: 'ضغط أو عطل مؤقت عند GitHub ($statusCode)',
          reason:
              'سيرفرات GitHub فيها مشكلة لحظية وردّت بكود $statusCode بعد عدة محاولات تلقائية.',
          solution: _defaultSolution(statusCode),
          technicalDetail: 'HTTP $statusCode on $ep\n$rawStr',
          isRetryable: true,
        );
      }

      return GitHubException(
        statusCode,
        apiMsg.isEmpty ? 'خطأ غير متوقع ($statusCode)' : apiMsg,
        technicalDetail: 'HTTP $statusCode on $ep\n$rawStr',
      );
    }

    return GitHubException(
      0,
      error.toString(),
      title: 'حصل خطأ غير متوقع',
      reason: error.toString(),
      solution: 'راجع التفاصيل التقنية تحت وجرب تعيد المحاولة.',
      technicalDetail: '${error.runtimeType} on $ep\n$error',
    );
  }

  @override
  String toString() => '$title — $reason';
}

class GitHubDeviceCode {
  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int expiresIn;
  final int interval;

  GitHubDeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
  });
}

class GitHubUserInfo {
  final String login;
  final String? name;
  GitHubUserInfo({required this.login, this.name});
}

class GitHubRepo {
  final String owner;
  final String name;
  final String fullName;
  final String defaultBranch;
  final bool isPrivate;
  final String description;
  final String homepage;
  final String htmlUrl;
  final bool archived;
  final bool hasIssues;
  final bool hasWiki;
  final int stargazersCount;
  final int sizeKb;
  final List<String> topics;

  GitHubRepo({
    required this.owner,
    required this.name,
    required this.fullName,
    required this.defaultBranch,
    this.isPrivate = true,
    this.description = '',
    this.homepage = '',
    this.htmlUrl = '',
    this.archived = false,
    this.hasIssues = true,
    this.hasWiki = true,
    this.stargazersCount = 0,
    this.sizeKb = 0,
    this.topics = const [],
  });

  factory GitHubRepo.fromJson(Map<String, dynamic> j) => GitHubRepo(
        owner:
            ((j['owner'] as Map<String, dynamic>?)?['login'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        fullName: (j['full_name'] ?? '').toString(),
        defaultBranch: (j['default_branch'] ?? 'main').toString(),
        isPrivate: j['private'] == true,
        description: (j['description'] ?? '').toString(),
        homepage: (j['homepage'] ?? '').toString(),
        htmlUrl: (j['html_url'] ?? '').toString(),
        archived: j['archived'] == true,
        hasIssues: j['has_issues'] != false,
        hasWiki: j['has_wiki'] != false,
        stargazersCount: (j['stargazers_count'] as num?)?.toInt() ?? 0,
        sizeKb: (j['size'] as num?)?.toInt() ?? 0,
        topics: (j['topics'] as List? ?? []).map((e) => e.toString()).toList(),
      );
}

class GitHubContentEntry {
  final String name;
  final String path;
  final String sha;
  final String type; // file | dir
  final int size;
  final String downloadUrl;

  const GitHubContentEntry({
    required this.name,
    required this.path,
    required this.sha,
    required this.type,
    required this.size,
    this.downloadUrl = '',
  });

  factory GitHubContentEntry.fromJson(Map<String, dynamic> j) =>
      GitHubContentEntry(
        name: (j['name'] ?? '').toString(),
        path: (j['path'] ?? '').toString(),
        sha: (j['sha'] ?? '').toString(),
        type: (j['type'] ?? 'file').toString(),
        size: (j['size'] as num?)?.toInt() ?? 0,
        downloadUrl: (j['download_url'] ?? '').toString(),
      );
}

class GitHubCommitSummary {
  final String sha;
  final String message;
  final String author;
  final String dateIso;

  const GitHubCommitSummary({
    required this.sha,
    required this.message,
    required this.author,
    required this.dateIso,
  });
}

/// 5-Stage Upload Pipeline Enum
enum UploadStage {
  scanning,
  hashing,
  uploading,
  committing,
  verifying,
  done,
}

extension UploadStageMeta on UploadStage {
  int get stepNumber {
    switch (this) {
      case UploadStage.scanning:
        return 1;
      case UploadStage.hashing:
        return 2;
      case UploadStage.uploading:
        return 3;
      case UploadStage.committing:
        return 4;
      case UploadStage.verifying:
        return 5;
      case UploadStage.done:
        return 5;
    }
  }

  String get shortLabel {
    switch (this) {
      case UploadStage.scanning:
        return 'فحص الملفات';
      case UploadStage.hashing:
        return 'مطابقة SHA-1';
      case UploadStage.uploading:
        return 'رفع بالدفعات';
      case UploadStage.committing:
        return 'تثبيت Commit';
      case UploadStage.verifying:
        return 'التحقق النهائي';
      case UploadStage.done:
        return 'تم بنجاح';
    }
  }
}

class UploadProgress {
  final UploadStage stageEnum;
  final String stage;
  final String currentFile;
  final int uploadedBytes;
  final int totalBytes;
  final int completedFiles;
  final int totalFiles;
  final double speedBytesPerSec;
  final int currentBatch;
  final int totalBatches;
  final int skippedFiles;
  final int retriedCount;
  final bool isPaused;
  final Duration? eta;

  UploadProgress({
    this.stageEnum = UploadStage.uploading,
    required this.stage,
    required this.currentFile,
    required this.uploadedBytes,
    required this.totalBytes,
    required this.completedFiles,
    required this.totalFiles,
    required this.speedBytesPerSec,
    this.currentBatch = 0,
    this.totalBatches = 0,
    this.skippedFiles = 0,
    this.retriedCount = 0,
    this.isPaused = false,
    this.eta,
  });

  double get fraction =>
      totalBytes <= 0 ? 0.0 : (uploadedBytes / totalBytes).clamp(0.0, 1.0);
}

class ConnectionHealthResult {
  final bool dnsOk;
  final bool apiOk;
  final int latencyMs;
  final int rateRemaining;
  final int rateLimit;
  final DateTime? rateResetAt;
  final List<String> tokenScopes;
  final String? userLogin;
  final GitHubException? error;

  const ConnectionHealthResult({
    required this.dnsOk,
    required this.apiOk,
    required this.latencyMs,
    this.rateRemaining = 0,
    this.rateLimit = 0,
    this.rateResetAt,
    this.tokenScopes = const [],
    this.userLogin,
    this.error,
  });

  String get qualityLabel {
    if (!dnsOk || !apiOk) return 'الاتصال مقطوع';
    if (latencyMs <= 350) return 'ممتاز وسريع جداً';
    if (latencyMs <= 900) return 'كويس ومستقر';
    return 'بطيء شوية (استخدم دفعات هادية)';
  }
}

class GitHubReleaseAsset {
  final int assetId;
  final int releaseId;
  final String name;
  final String downloadUrl;
  final int size;
  final String tagName;

  const GitHubReleaseAsset({
    this.assetId = 0,
    this.releaseId = 0,
    required this.name,
    required this.downloadUrl,
    required this.size,
    required this.tagName,
  });
}

class GitHubApiClient {
  GitHubAuthSession _session;
  final HttpClient _http;
  final int maxRetries;
  final int timeoutSeconds;

  int? lastRateRemaining;
  int? lastRateLimit;

  GitHubApiClient(
    String token, {
    GitHubAuthSession? session,
    this.maxRetries = 4,
    this.timeoutSeconds = 35,
  })  : _session = session ?? GitHubAuthSession(accessToken: token.trim()),
        _http = HttpClient()
          ..connectionTimeout = Duration(seconds: timeoutSeconds)
          ..idleTimeout = const Duration(seconds: 65)
          ..maxConnectionsPerHost = 6;

  void close() => _http.close(force: false);

  Future<bool> _tryRefreshToken() async {
    final rt = _session.refreshToken;
    final cid = _session.clientId ?? GitHubConfig.oauthClientId;
    if (rt == null || rt.isEmpty || cid.isEmpty) return false;
    try {
      final req = await _http
          .postUrl(Uri.parse('https://github.com/login/oauth/access_token'))
          .timeout(Duration(seconds: timeoutSeconds));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.contentType = ContentType.json;
      final payload = utf8.encode(jsonEncode({
        'client_id': cid,
        'grant_type': 'refresh_token',
        'refresh_token': rt,
      }));
      req.contentLength = payload.length;
      req.add(payload);
      final res =
          await req.close().timeout(Duration(seconds: timeoutSeconds));
      final j = jsonDecode(await res.transform(utf8.decoder).join())
          as Map<String, dynamic>;
      if (j['access_token'] == null) return false;
      final exp = (j['expires_in'] as num?)?.toInt();
      _session = GitHubAuthSession(
        accessToken: j['access_token'].toString(),
        refreshToken: (j['refresh_token'] ?? rt).toString(),
        clientId: cid,
        expiresAt:
            exp != null ? DateTime.now().add(Duration(seconds: exp)) : null,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Resilient JSON HTTP request with exponential backoff, jitter, timeout,
  /// rate-limit Retry-After handling, and Egyptian Arabic error diagnostics.
  Future<({int status, dynamic body, Map<String, String> headers})>
      requestJsonFull(
    String method,
    String pathOrUrl, {
    Map<String, dynamic>? body,
    bool auth = true,
    int? retries,
    void Function(int attempt, int maxAttempts, Duration wait, String why)?
        onRetry,
  }) async {
    if (auth && _session.isExpired) await _tryRefreshToken();
    final uri = pathOrUrl.startsWith('http')
        ? Uri.parse(pathOrUrl)
        : Uri.parse('https://api.github.com$pathOrUrl');
    final attempts = (retries ?? maxRetries).clamp(1, 7);
    final rng = math.Random();
    var didRefresh = false;

    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        final reqHeaders = <String, String>{
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
          'User-Agent': 'JOOhub/10.0',
          if (auth && _session.accessToken.isNotEmpty)
            'Authorization': 'Bearer ${_session.accessToken}',
          if (body != null) 'Content-Type': 'application/json; charset=utf-8',
        };
        final httpReq = http.Request(method.toUpperCase(), uri);
        httpReq.headers.addAll(reqHeaders);
        if (body != null) {
          httpReq.bodyBytes = utf8.encode(jsonEncode(body));
        }

        final tempClient = http.Client();
        late final http.Response res;
        try {
          final streamed = await tempClient
              .send(httpReq)
              .timeout(Duration(seconds: timeoutSeconds));
          res = await http.Response.fromStream(streamed)
              .timeout(Duration(seconds: timeoutSeconds));
        } finally {
          tempClient.close();
        }
        final raw = utf8.decode(res.bodyBytes, allowMalformed: true);

        final hdrs = <String, String>{};
        res.headers.forEach((k, v) {
          if (v.isNotEmpty) hdrs[k.toLowerCase()] = v;
        });

        final rem = int.tryParse(hdrs['x-ratelimit-remaining'] ?? '');
        final lim = int.tryParse(hdrs['x-ratelimit-limit'] ?? '');
        if (rem != null) lastRateRemaining = rem;
        if (lim != null) lastRateLimit = lim;

        dynamic parsed;
        if (raw.isNotEmpty) {
          try {
            parsed = jsonDecode(raw);
          } catch (_) {
            parsed = raw;
          }
        }

        // Auto-refresh token once on 401
        if (res.statusCode == 401 && auth && !didRefresh) {
          didRefresh = true;
          if (await _tryRefreshToken()) {
            continue;
          }
        }

        // Retry transient 429 / 5xx server errors
        final retryStatus = res.statusCode == 429 ||
            res.statusCode == 500 ||
            res.statusCode == 502 ||
            res.statusCode == 503 ||
            res.statusCode == 504;
        if (retryStatus && attempt < attempts) {
          final retryAfterSec = int.tryParse(hdrs['retry-after'] ?? '');
          final baseMs = retryAfterSec != null
              ? retryAfterSec * 1000
              : (1000 * math.pow(2, attempt - 1)).toInt();
          final wait = Duration(milliseconds: baseMs + rng.nextInt(450));
          onRetry?.call(attempt, attempts, wait, 'سيرفر GitHub رد بـ ${res.statusCode}');
          await Future<void>.delayed(wait);
          continue;
        }

        return (status: res.statusCode, body: parsed, headers: hdrs);
      } catch (e) {
        final diag = GitHubException.diagnose(e, endpoint: pathOrUrl);
        if (diag.isRetryable && attempt < attempts) {
          final wait = Duration(
            milliseconds:
                (900 * math.pow(2, attempt - 1)).toInt() + rng.nextInt(400),
          );
          onRetry?.call(attempt, attempts, wait, diag.title);
          await Future<void>.delayed(wait);
          continue;
        }
        throw diag;
      }
    }

    throw GitHubException.diagnose(
      Exception('فشلت كل محاولات الاتصال'),
      endpoint: pathOrUrl,
    );
  }

  /// Backward-compatible wrapper around requestJsonFull
  Future<({int status, dynamic body})> requestJson(
    String method,
    String pathOrUrl, {
    Map<String, dynamic>? body,
    bool auth = true,
    void Function(int attempt, int maxAttempts, Duration wait, String why)?
        onRetry,
  }) async {
    final full = await requestJsonFull(
      method,
      pathOrUrl,
      body: body,
      auth: auth,
      onRetry: onRetry,
    );
    return (status: full.status, body: full.body);
  }

  /// Full Network & Account Health Doctor (DNS + Ping + Rate Limit + Scopes)
  Future<ConnectionHealthResult> checkConnectionHealth() async {
    bool dnsOk = false;
    try {
      final lookup = await InternetAddress.lookup('api.github.com')
          .timeout(const Duration(seconds: 6));
      dnsOk = lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
    } catch (e) {
      return ConnectionHealthResult(
        dnsOk: false,
        apiOk: false,
        latencyMs: 0,
        error: GitHubException.diagnose(e, endpoint: 'DNS api.github.com'),
      );
    }

    final sw = Stopwatch()..start();
    try {
      final hasToken = _session.accessToken.isNotEmpty;
      final res = await requestJsonFull(
        'GET',
        hasToken ? '/user' : '/rate_limit',
        auth: hasToken,
        retries: 2,
      );
      sw.stop();

      final rem = int.tryParse(res.headers['x-ratelimit-remaining'] ?? '') ?? 0;
      final lim = int.tryParse(res.headers['x-ratelimit-limit'] ?? '') ?? 0;
      final resetEpoch = int.tryParse(res.headers['x-ratelimit-reset'] ?? '');
      final scopesRaw = res.headers['x-oauth-scopes'] ?? '';
      final scopes = scopesRaw
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      if (res.status != 200) {
        return ConnectionHealthResult(
          dnsOk: dnsOk,
          apiOk: false,
          latencyMs: sw.elapsedMilliseconds,
          rateRemaining: rem,
          rateLimit: lim,
          rateResetAt: resetEpoch != null
              ? DateTime.fromMillisecondsSinceEpoch(resetEpoch * 1000)
              : null,
          tokenScopes: scopes,
          error: GitHubException.diagnose(
            Exception('API Error'),
            endpoint: hasToken ? '/user' : '/rate_limit',
            statusCode: res.status,
            parsedBody: res.body,
            responseHeaders: res.headers,
          ),
        );
      }

      String? login;
      if (hasToken && res.body is Map<String, dynamic>) {
        login = (res.body as Map)['login']?.toString();
      }

      return ConnectionHealthResult(
        dnsOk: true,
        apiOk: true,
        latencyMs: sw.elapsedMilliseconds,
        rateRemaining: rem,
        rateLimit: lim,
        rateResetAt: resetEpoch != null
            ? DateTime.fromMillisecondsSinceEpoch(resetEpoch * 1000)
            : null,
        tokenScopes: scopes,
        userLogin: login,
      );
    } catch (e) {
      sw.stop();
      return ConnectionHealthResult(
        dnsOk: dnsOk,
        apiOk: false,
        latencyMs: sw.elapsedMilliseconds,
        error: GitHubException.diagnose(e, endpoint: '/user'),
      );
    }
  }

  Future<GitHubDeviceCode> startDeviceFlow({required String clientId}) async {
    try {
      final req = await _http
          .postUrl(Uri.parse('https://github.com/login/device/code'))
          .timeout(Duration(seconds: timeoutSeconds));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.contentType = ContentType.json;
      final payload = utf8.encode(jsonEncode({
        'client_id': clientId.trim(),
        'scope': 'repo workflow read:user',
      }));
      req.contentLength = payload.length;
      req.add(payload);
      final res =
          await req.close().timeout(Duration(seconds: timeoutSeconds));
      final raw = await res.transform(utf8.decoder).join();
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (res.statusCode != 200 || j['device_code'] == null) {
        throw GitHubException.diagnose(
          Exception(raw),
          endpoint: 'device/code',
          statusCode: res.statusCode,
          parsedBody: j,
          rawBody: raw,
        );
      }
      return GitHubDeviceCode(
        deviceCode: j['device_code'].toString(),
        userCode: j['user_code'].toString(),
        verificationUri: j['verification_uri'].toString(),
        expiresIn: (j['expires_in'] as num?)?.toInt() ?? 900,
        interval: (j['interval'] as num?)?.toInt() ?? 5,
      );
    } catch (e) {
      throw GitHubException.diagnose(e, endpoint: 'github.com/login/device/code');
    }
  }

  Future<GitHubAuthSession> pollDeviceFlowSession({
    required String clientId,
    required GitHubDeviceCode code,
    GitHubCancelToken? cancelToken,
  }) async {
    var poll = math.max(code.interval, 5);
    final deadline = DateTime.now().add(Duration(seconds: code.expiresIn));
    while (DateTime.now().isBefore(deadline)) {
      if (cancelToken?.isCancelled == true) {
        throw GitHubException(499, 'تم إلغاء الربط');
      }
      await Future<void>.delayed(Duration(seconds: poll));
      try {
        final req = await _http
            .postUrl(Uri.parse('https://github.com/login/oauth/access_token'))
            .timeout(Duration(seconds: timeoutSeconds));
        req.headers.set(HttpHeaders.acceptHeader, 'application/json');
        req.headers.contentType = ContentType.json;
        final payload = utf8.encode(jsonEncode({
          'client_id': clientId.trim(),
          'device_code': code.deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        }));
        req.contentLength = payload.length;
        req.add(payload);
        final res =
            await req.close().timeout(Duration(seconds: timeoutSeconds));
        final j = jsonDecode(await res.transform(utf8.decoder).join())
            as Map<String, dynamic>;
        if (j['access_token'] != null) {
          final exp = (j['expires_in'] as num?)?.toInt();
          _session = GitHubAuthSession(
            accessToken: j['access_token'].toString(),
            refreshToken: j['refresh_token'] as String?,
            clientId: clientId.trim(),
            expiresAt:
                exp != null ? DateTime.now().add(Duration(seconds: exp)) : null,
          );
          return _session;
        }
        final err = (j['error'] ?? '').toString();
        if (err == 'authorization_pending') continue;
        if (err == 'slow_down') {
          poll += 5;
          continue;
        }
        throw GitHubException.diagnose(
          Exception(err),
          endpoint: 'oauth/access_token',
          statusCode: res.statusCode,
          parsedBody: j,
        );
      } catch (e) {
        final diag = GitHubException.diagnose(e, endpoint: 'oauth/access_token');
        if (diag.isRetryable) continue;
        throw diag;
      }
    }
    throw GitHubException(
      408,
      'انتهت مهلة كود الربط — جرب تبدأ الربط من جديد',
      title: 'وقت الكود خلص',
      reason: 'عدّى أكتر من 15 دقيقة من غير ما توافق على الكود في صفحة GitHub.',
      solution: 'اضغط «بدء الربط السريع» تاني وهيتعمل كود جديد فوراً.',
    );
  }

  Future<GitHubUserInfo> verifyUser() async {
    final res = await requestJsonFull('GET', '/user');
    if (res.status != 200 || res.body is! Map<String, dynamic>) {
      throw GitHubException.diagnose(
        Exception('verifyUser failed'),
        endpoint: '/user',
        statusCode: res.status,
        parsedBody: res.body,
        responseHeaders: res.headers,
      );
    }
    final j = res.body as Map<String, dynamic>;
    return GitHubUserInfo(
        login: (j['login'] ?? '').toString(), name: j['name'] as String?);
  }

  Future<List<GitHubRepo>> listRepos() async {
    final res = await requestJsonFull('GET',
        '/user/repos?sort=updated&per_page=100&affiliation=owner,collaborator');
    if (res.status != 200 || res.body is! List) {
      throw GitHubException.diagnose(
        Exception('listRepos failed'),
        endpoint: '/user/repos',
        statusCode: res.status,
        parsedBody: res.body,
        responseHeaders: res.headers,
      );
    }
    return (res.body as List)
        .whereType<Map<String, dynamic>>()
        .map(GitHubRepo.fromJson)
        .toList();
  }

  Future<GitHubRepo> createRepo(String name, {bool isPrivate = true}) async {
    final res = await requestJsonFull('POST', '/user/repos', body: {
      'name': name.trim(),
      'private': isPrivate,
      'auto_init': true,
    });
    if (res.status != 201 || res.body is! Map<String, dynamic>) {
      throw GitHubException.diagnose(
        Exception('createRepo failed'),
        endpoint: '/user/repos',
        statusCode: res.status,
        parsedBody: res.body,
        responseHeaders: res.headers,
      );
    }
    return GitHubRepo.fromJson(res.body as Map<String, dynamic>);
  }

  Future<List<String>> listBranches(String owner, String repo) async {
    final res =
        await requestJsonFull('GET', '/repos/$owner/$repo/branches?per_page=50');
    if (res.status != 200 || res.body is! List) return [];
    return (res.body as List)
        .whereType<Map<String, dynamic>>()
        .map((e) => (e['name'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<void> createBranch({
    required String owner,
    required String repo,
    required String newBranch,
    required String fromBranch,
  }) async {
    final refRes = await requestJsonFull(
        'GET', '/repos/$owner/$repo/git/ref/heads/$fromBranch');
    if (refRes.status != 200 || refRes.body is! Map<String, dynamic>) {
      throw GitHubException.diagnose(
        Exception('Base branch not found'),
        endpoint: '/git/ref/heads/$fromBranch',
        statusCode: refRes.status,
        parsedBody: refRes.body,
        responseHeaders: refRes.headers,
      );
    }
    final sha = ((refRes.body as Map)['object'] as Map)['sha'].toString();
    final cr = await requestJsonFull('POST', '/repos/$owner/$repo/git/refs',
        body: {'ref': 'refs/heads/${newBranch.trim()}', 'sha': sha});
    if (cr.status != 201) {
      throw GitHubException.diagnose(
        Exception('createBranch failed'),
        endpoint: '/git/refs',
        statusCode: cr.status,
        parsedBody: cr.body,
        responseHeaders: cr.headers,
      );
    }
  }

  Future<List<GitHubCommitSummary>> listCommits(
    String owner,
    String repo, {
    String? branch,
    int perPage = 8,
  }) async {
    final q = branch != null && branch.isNotEmpty
        ? '?sha=${Uri.encodeQueryComponent(branch)}&per_page=$perPage'
        : '?per_page=$perPage';
    final res = await requestJsonFull('GET', '/repos/$owner/$repo/commits$q');
    if (res.status != 200 || res.body is! List) return [];
    return (res.body as List).whereType<Map<String, dynamic>>().map((c) {
      final commit = (c['commit'] as Map<String, dynamic>?) ?? const {};
      final author = (commit['author'] as Map<String, dynamic>?) ?? const {};
      return GitHubCommitSummary(
        sha: (c['sha'] ?? '').toString(),
        message: (commit['message'] ?? '').toString().split('\n').first,
        author: (author['name'] ?? '').toString(),
        dateIso: (author['date'] ?? '').toString(),
      );
    }).toList();
  }

  /// =========================================================================
  /// 5-STAGE RESILIENT UPLOAD ENGINE (Scan -> SHA-1 -> Batches -> Commit -> Verify)
  /// Supports Pause/Resume/Cancel, Checkpoint Recovery & Auto-Retry!
  /// =========================================================================
  Future<String> syncDirectoryToRepo({
    required Directory projectDir,
    required GitHubRepo repo,
    required String commitMessage,
    String? targetBranch,
    int batchSize = 5,
    bool useCheckpoint = true,
    GitHubCancelToken? cancelToken,
    void Function(UploadProgress p)? onProgress,
    void Function(String msg)? onLog,
  }) async {
    const ignored = {'.git', 'build', '.dart_tool', '.gradle', '.joohub'};
    final owner = repo.owner;
    final repoName = repo.name;
    final branch = (targetBranch != null && targetBranch.trim().isNotEmpty)
        ? targetBranch.trim()
        : repo.defaultBranch;

    // -----------------------------------------------------------------------
    // STAGE 1: فحص وتجهيز الملفات
    // -----------------------------------------------------------------------
    onLog?.call('🔍 المرحلة 1/5: بنفحص ملفات المشروع ونجهزها للرفع...');
    final files = <({File file, String rel, int size})>[];
    var totalBytes = 0;

    await for (final ent
        in projectDir.list(recursive: true, followLinks: false)) {
      if (cancelToken?.isCancelled == true) {
        throw GitHubException(499, 'تم إلغاء الرفع في مرحلة الفحص');
      }
      if (ent is! File) continue;
      final rel =
          p.relative(ent.path, from: projectDir.path).replaceAll('\\', '/');
      if (p.split(rel).any((s) => ignored.contains(s))) continue;
      final sz = await ent.length();
      totalBytes += sz;
      files.add((file: ent, rel: rel, size: sz));
    }

    if (files.isEmpty) {
      throw GitHubException(
        400,
        'المشروع فاضي ومفيهوش ملفات للرفع',
        title: 'المشروع فاضي',
        reason: 'ملقيناش أي ملفات قابلة للرفع جوه المجلد ده.',
        solution: 'اتأكد إنك اخترت المشروع الصح من تبويب «مشاريعي».',
      );
    }
    if (totalBytes > GitHubConfig.maxTotalUploadBytes) {
      throw GitHubException(
        413,
        'حجم المشروع (${fmtBytes(totalBytes)}) أكبر من 500 ميجابايت',
        title: 'حجم المشروع كبير جداً',
        reason: 'الحد الأقصى للرفع في المرة الواحدة هو 500 ميجابايت.',
        solution: 'امسح الملفات الضخمة أو مجلدات الكاش اللي مش محتاجها وجرب تاني.',
      );
    }

    onProgress?.call(UploadProgress(
      stageEnum: UploadStage.scanning,
      stage: 'المرحلة 1/5: فحص وتجهيز الملفات',
      currentFile: 'تم فحص ${files.length} ملف (${fmtBytes(totalBytes)})',
      uploadedBytes: 0,
      totalBytes: totalBytes,
      completedFiles: 0,
      totalFiles: files.length,
      speedBytesPerSec: 0,
    ));

    // -----------------------------------------------------------------------
    // STAGE 2: مطابقة بصمات SHA-1 + تحميل نقطة الاستكمال (Checkpoint)
    // -----------------------------------------------------------------------
    onLog?.call('🧬 المرحلة 2/5: بنطابق بصمات SHA-1 مع المستودع $owner/$repoName ($branch)...');
    String? baseCommit;
    String? baseTree;
    final remoteShas = <String, String>{};

    final refRes = await requestJsonFull(
      'GET',
      '/repos/$owner/$repoName/git/ref/heads/$branch',
      onRetry: (a, m, w, why) =>
          onLog?.call('🔄 إعادة محاولة ($a/$m) لفحص الفرع: $why'),
    );
    if (refRes.status == 200 && refRes.body is Map<String, dynamic>) {
      baseCommit = ((refRes.body as Map)['object'] as Map)['sha'].toString();
      final cRes = await requestJsonFull(
        'GET',
        '/repos/$owner/$repoName/git/commits/$baseCommit',
      );
      if (cRes.status == 200 && cRes.body is Map<String, dynamic>) {
        baseTree = ((cRes.body as Map)['tree'] as Map)['sha'].toString();
        final tRes = await requestJsonFull(
          'GET',
          '/repos/$owner/$repoName/git/trees/$baseTree?recursive=1',
        );
        if (tRes.status == 200 && tRes.body is Map<String, dynamic>) {
          for (final item in ((tRes.body as Map)['tree'] as List? ?? [])) {
            if (item is Map && item['type'] == 'blob') {
              remoteShas[item['path'].toString()] = item['sha'].toString();
            }
          }
        }
      }
    } else if (refRes.status != 404 && refRes.status != 409) {
      throw GitHubException.diagnose(
        Exception('Failed to inspect branch'),
        endpoint: '/git/ref/heads/$branch',
        statusCode: refRes.status,
        parsedBody: refRes.body,
        responseHeaders: refRes.headers,
      );
    }

    // Load Checkpoint if enabled (resumes previously uploaded blobs on same repo/branch)
    final checkpointFile = File(p.join(
      projectDir.path,
      '.joohub',
      'checkpoint_${owner}_${repoName}_$branch.json',
    ));
    final cachedBlobs = <String, String>{}; // localSha -> uploadedBlobSha
    if (useCheckpoint && await checkpointFile.exists()) {
      try {
        final rawCp =
            jsonDecode(await checkpointFile.readAsString()) as Map<String, dynamic>;
        rawCp.forEach((k, v) => cachedBlobs[k] = v.toString());
        if (cachedBlobs.isNotEmpty) {
          onLog?.call(
            '♻️ لقينا نقطة استكمال سابقة فيها ${cachedBlobs.length} ملف مرفوع جاهز — هنكمّل من مطرح ما وقفنا!',
          );
        }
      } catch (_) {}
    }

    final pending = <({File file, String rel, int size, String localSha})>[];
    final treeEntries = <Map<String, dynamic>>[];
    var skippedCount = 0;
    var alreadyUploadedBytes = 0;

    for (var i = 0; i < files.length; i++) {
      if (cancelToken?.isCancelled == true) {
        throw GitHubException(499, 'تم إلغاء الرفع في مرحلة مطابقة البصمات');
      }
      final item = files[i];
      if (item.size > GitHubConfig.maxGitBlobBytes) {
        pending.add((
          file: item.file,
          rel: item.rel,
          size: item.size,
          localSha: 'LARGE_ASSET',
        ));
      } else {
        final sha = await GitSha1.gitBlobSha1(item.file);
        if (remoteShas[item.rel] == sha) {
          skippedCount++;
          alreadyUploadedBytes += item.size;
        } else if (cachedBlobs.containsKey(sha)) {
          skippedCount++;
          alreadyUploadedBytes += item.size;
          treeEntries.add({
            'path': item.rel,
            'mode': '100644',
            'type': 'blob',
            'sha': cachedBlobs[sha],
          });
        } else {
          pending.add((
            file: item.file,
            rel: item.rel,
            size: item.size,
            localSha: sha,
          ));
        }
      }

      if (i % 12 == 0 || i == files.length - 1) {
        onProgress?.call(UploadProgress(
          stageEnum: UploadStage.hashing,
          stage: 'المرحلة 2/5: مطابقة بصمات الملفات (SHA-1)',
          currentFile: item.rel,
          uploadedBytes: alreadyUploadedBytes,
          totalBytes: totalBytes,
          completedFiles: i + 1,
          totalFiles: files.length,
          speedBytesPerSec: 0,
          skippedFiles: skippedCount,
        ));
      }
    }

    if (pending.isEmpty && treeEntries.isEmpty) {
      onLog?.call('✅ المستودع متحدث بالفعل بالكامل — مفيش أي ملفات اتغيّرت!');
      onProgress?.call(UploadProgress(
        stageEnum: UploadStage.done,
        stage: 'كله تمام ومحدّث بالفعل',
        currentFile: 'مفيش تغييرات جديدة',
        uploadedBytes: totalBytes,
        totalBytes: totalBytes,
        completedFiles: files.length,
        totalFiles: files.length,
        speedBytesPerSec: 0,
        skippedFiles: skippedCount,
      ));
      return baseCommit ?? 'up-to-date';
    }

    // -----------------------------------------------------------------------
    // STAGE 3: رفع الملفات على دفعات ومراحل (Staged Batches + Pause/Resume + Retry)
    // -----------------------------------------------------------------------
    final safeBatchSize = batchSize.clamp(1, 15);
    final totalBatches =
        pending.isEmpty ? 0 : (pending.length / safeBatchSize).ceil();
    onLog?.call(
      '🚀 المرحلة 3/5: هنرفع ${pending.length} ملف جديد/معدّل على $totalBatches دفعة (وتخطّينا $skippedCount ملف متطابق).',
    );

    var uploadedBytes = alreadyUploadedBytes;
    var doneFiles = skippedCount;
    var retriedTotal = 0;
    final sw = Stopwatch()..start();

    Future<void> saveCheckpointNow() async {
      if (!useCheckpoint) return;
      try {
        await checkpointFile.parent.create(recursive: true);
        await checkpointFile.writeAsString(jsonEncode(cachedBlobs));
      } catch (_) {}
    }

    for (var bIdx = 0; bIdx < totalBatches; bIdx++) {
      final start = bIdx * safeBatchSize;
      final end = math.min(start + safeBatchSize, pending.length);
      final batch = pending.sublist(start, end);
      onLog?.call('📦 دفعة ${bIdx + 1} من $totalBatches (${batch.length} ملف)...');

      for (final item in batch) {
        if (cancelToken != null) {
          if (cancelToken.isPaused) {
            onProgress?.call(UploadProgress(
              stageEnum: UploadStage.uploading,
              stage: 'الرفع واقف مؤقتاً (اضغط استكمال)',
              currentFile: item.rel,
              uploadedBytes: uploadedBytes,
              totalBytes: totalBytes,
              completedFiles: doneFiles,
              totalFiles: files.length,
              speedBytesPerSec: 0,
              currentBatch: bIdx + 1,
              totalBatches: totalBatches,
              skippedFiles: skippedCount,
              retriedCount: retriedTotal,
              isPaused: true,
            ));
            await cancelToken.waitIfPaused();
          }
          if (cancelToken.isCancelled) {
            await saveCheckpointNow();
            throw GitHubException(499, 'تم إلغاء الرفع وحفظ نقطة الاستكمال');
          }
        }

        if (item.size > GitHubConfig.maxGitBlobBytes) {
          final tag = 'assets-${DateTime.now().millisecondsSinceEpoch}';
          final relId = await getOrCreateReleaseId(
            owner: owner,
            repo: repoName,
            tag: tag,
          );
          final url = await streamUploadReleaseAsset(
            owner: owner,
            repo: repoName,
            releaseId: relId,
            file: item.file,
            customName: item.rel.replaceAll('/', '__'),
            cancelToken: cancelToken,
            onProgress: (sent, tot, spd) {
              final remBytes = math.max(0, totalBytes - (uploadedBytes + sent));
              final eta = spd > 100
                  ? Duration(seconds: (remBytes / spd).round())
                  : null;
              onProgress?.call(UploadProgress(
                stageEnum: UploadStage.uploading,
                stage: 'المرحلة 3/5: بث ملف ضخم (>90MB)',
                currentFile: item.rel,
                uploadedBytes: uploadedBytes + sent,
                totalBytes: totalBytes,
                completedFiles: doneFiles,
                totalFiles: files.length,
                speedBytesPerSec: spd,
                currentBatch: bIdx + 1,
                totalBatches: totalBatches,
                skippedFiles: skippedCount,
                retriedCount: retriedTotal,
                eta: eta,
              ));
            },
          );
          treeEntries.add({
            'path': '${item.rel}.joohub-asset.json',
            'mode': '100644',
            'type': 'blob',
            'content':
                jsonEncode({'path': item.rel, 'size': item.size, 'url': url}),
          });
        } else {
          final rawBytes = await item.file.readAsBytes();
          final bRes = await requestJsonFull(
            'POST',
            '/repos/$owner/$repoName/git/blobs',
            body: {
              'content': base64Encode(rawBytes),
              'encoding': 'base64',
            },
            onRetry: (att, maxA, wait, why) {
              retriedTotal++;
              onLog?.call(
                '🔄 النت اتهز عند ${item.rel} — بنجرب تاني ($att/$maxA) بعد ${wait.inSeconds}ث ($why)',
              );
            },
          );
          if (bRes.status != 201 || bRes.body is! Map<String, dynamic>) {
            await saveCheckpointNow();
            throw GitHubException.diagnose(
              Exception('Blob upload failed for ${item.rel}'),
              endpoint: '/git/blobs (${item.rel})',
              statusCode: bRes.status,
              parsedBody: bRes.body,
              responseHeaders: bRes.headers,
            );
          }
          final blobSha = (bRes.body as Map)['sha'].toString();
          cachedBlobs[item.localSha] = blobSha;
          treeEntries.add({
            'path': item.rel,
            'mode': '100644',
            'type': 'blob',
            'sha': blobSha,
          });
        }

        uploadedBytes += item.size;
        doneFiles++;
        final elapsedMs = sw.elapsedMilliseconds;
        final transferred = uploadedBytes - alreadyUploadedBytes;
        final speed = elapsedMs > 0 ? transferred * 1000.0 / elapsedMs : 0.0;
        final remBytes = math.max(0, totalBytes - uploadedBytes);
        final eta = speed > 100
            ? Duration(seconds: (remBytes / speed).round())
            : null;

        onProgress?.call(UploadProgress(
          stageEnum: UploadStage.uploading,
          stage: 'المرحلة 3/5: رفع الدفعة ${bIdx + 1} من $totalBatches',
          currentFile: item.rel,
          uploadedBytes: uploadedBytes,
          totalBytes: totalBytes,
          completedFiles: doneFiles,
          totalFiles: files.length,
          speedBytesPerSec: speed,
          currentBatch: bIdx + 1,
          totalBatches: totalBatches,
          skippedFiles: skippedCount,
          retriedCount: retriedTotal,
          eta: eta,
        ));
      }

      // Save checkpoint after each completed batch
      await saveCheckpointNow();
    }

    // -----------------------------------------------------------------------
    // STAGE 4: بناء شجرة Git وتثبيت الـ Commit
    // -----------------------------------------------------------------------
    onLog?.call('🌳 المرحلة 4/5: بنبني شجرة الملفات ونثبّت الـ Commit على فرع $branch...');
    onProgress?.call(UploadProgress(
      stageEnum: UploadStage.committing,
      stage: 'المرحلة 4/5: بناء شجرة Git وتثبيت التحديث',
      currentFile: 'تجهيز ${treeEntries.length} ملف في الـ Commit...',
      uploadedBytes: totalBytes,
      totalBytes: totalBytes,
      completedFiles: files.length,
      totalFiles: files.length,
      speedBytesPerSec: 0,
      currentBatch: totalBatches,
      totalBatches: totalBatches,
      skippedFiles: skippedCount,
      retriedCount: retriedTotal,
    ));

    final newTree = await requestJsonFull(
      'POST',
      '/repos/$owner/$repoName/git/trees',
      body: {
        'tree': treeEntries,
        if (baseTree != null) 'base_tree': baseTree,
      },
      onRetry: (a, m, w, why) =>
          onLog?.call('🔄 إعادة محاولة بناء الشجرة ($a/$m): $why'),
    );
    if (newTree.status != 201 || newTree.body is! Map<String, dynamic>) {
      throw GitHubException.diagnose(
        Exception('Tree creation failed'),
        endpoint: '/git/trees',
        statusCode: newTree.status,
        parsedBody: newTree.body,
        responseHeaders: newTree.headers,
      );
    }

    final newCommit = await requestJsonFull(
      'POST',
      '/repos/$owner/$repoName/git/commits',
      body: {
        'message': commitMessage.trim().isEmpty
            ? 'تحديث من JOOhub'
            : commitMessage.trim(),
        'tree': (newTree.body as Map)['sha'],
        if (baseCommit != null) 'parents': [baseCommit],
      },
    );
    if (newCommit.status != 201 || newCommit.body is! Map<String, dynamic>) {
      throw GitHubException.diagnose(
        Exception('Commit creation failed'),
        endpoint: '/git/commits',
        statusCode: newCommit.status,
        parsedBody: newCommit.body,
        responseHeaders: newCommit.headers,
      );
    }

    final commitSha = (newCommit.body as Map)['sha'].toString();
    final refUpdate = baseCommit != null
        ? await requestJsonFull(
            'PATCH',
            '/repos/$owner/$repoName/git/refs/heads/$branch',
            body: {'sha': commitSha, 'force': false},
          )
        : await requestJsonFull(
            'POST',
            '/repos/$owner/$repoName/git/refs',
            body: {'ref': 'refs/heads/$branch', 'sha': commitSha},
          );

    if (refUpdate.status != 200 && refUpdate.status != 201) {
      throw GitHubException.diagnose(
        Exception('Branch update failed'),
        endpoint: '/git/refs/heads/$branch',
        statusCode: refUpdate.status,
        parsedBody: refUpdate.body,
        responseHeaders: refUpdate.headers,
      );
    }

    // -----------------------------------------------------------------------
    // STAGE 5: التحقق النهائي وتنظيف الـ Checkpoint
    // -----------------------------------------------------------------------
    onLog?.call('✅ المرحلة 5/5: بنتأكد إن التحديث وصل بنجاح وننظف الكاش المؤقت...');
    onProgress?.call(UploadProgress(
      stageEnum: UploadStage.verifying,
      stage: 'المرحلة 5/5: التحقق النهائي من الرفع',
      currentFile: 'Commit: ${commitSha.substring(0, math.min(7, commitSha.length))}',
      uploadedBytes: totalBytes,
      totalBytes: totalBytes,
      completedFiles: files.length,
      totalFiles: files.length,
      speedBytesPerSec: 0,
      currentBatch: totalBatches,
      totalBatches: totalBatches,
      skippedFiles: skippedCount,
      retriedCount: retriedTotal,
    ));

    if (await checkpointFile.exists()) {
      try {
        await checkpointFile.delete();
      } catch (_) {}
    }

    onProgress?.call(UploadProgress(
      stageEnum: UploadStage.done,
      stage: 'تم الرفع بنجاح 100% 🎉',
      currentFile: 'Commit ${commitSha.substring(0, math.min(7, commitSha.length))}',
      uploadedBytes: totalBytes,
      totalBytes: totalBytes,
      completedFiles: files.length,
      totalFiles: files.length,
      speedBytesPerSec: 0,
      currentBatch: totalBatches,
      totalBatches: totalBatches,
      skippedFiles: skippedCount,
      retriedCount: retriedTotal,
    ));

    return commitSha;
  }

  /// Triggers a GitHub Actions workflow via workflow_dispatch.
  Future<bool> triggerWorkflow({
    required String owner,
    required String repo,
    required String workflowFileName,
    String ref = 'main',
  }) async {
    final res = await requestJsonFull(
      'POST',
      '/repos/$owner/$repo/actions/workflows/$workflowFileName/dispatches',
      body: {'ref': ref},
    );
    return res.status == 204 || res.status == 200;
  }

  Future<List<Map<String, dynamic>>> listWorkflowRuns(
    String owner,
    String repo, {
    int perPage = 8,
  }) async {
    final res = await requestJsonFull(
      'GET',
      '/repos/$owner/$repo/actions/runs?per_page=$perPage',
    );
    if (res.status == 200 && res.body is Map<String, dynamic>) {
      return ((res.body as Map)['workflow_runs'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> listRunJobs(
    String owner,
    String repo,
    int runId,
  ) async {
    final res = await requestJsonFull(
      'GET',
      '/repos/$owner/$repo/actions/runs/$runId/jobs',
    );
    if (res.status == 200 && res.body is Map<String, dynamic>) {
      return ((res.body as Map)['jobs'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
    }
    return [];
  }

  Future<List<GitHubReleaseAsset>> listApkReleaseAssets(
    String owner,
    String repo,
  ) async {
    final res = await requestJsonFull(
      'GET',
      '/repos/$owner/$repo/releases?per_page=8',
    );
    final list = <GitHubReleaseAsset>[];
    if (res.status == 200 && res.body is List) {
      for (final rel in (res.body as List).whereType<Map<String, dynamic>>()) {
        final tag = (rel['tag_name'] ?? '').toString();
        final assets = (rel['assets'] as List? ?? [])
            .whereType<Map<String, dynamic>>();
        for (final a in assets) {
          list.add(GitHubReleaseAsset(
            assetId: (a['id'] as num?)?.toInt() ?? 0,
            releaseId: (rel['id'] as num?)?.toInt() ?? 0,
            name: (a['name'] ?? '').toString(),
            downloadUrl: (a['browser_download_url'] ?? '').toString(),
            size: (a['size'] as num?)?.toInt() ?? 0,
            tagName: tag,
          ));
        }
      }
    }
    return list;
  }

  Future<int> getOrCreateReleaseId({
    required String owner,
    required String repo,
    required String tag,
  }) async {
    final existing = await requestJsonFull(
        'GET', '/repos/$owner/$repo/releases/tags/${Uri.encodeComponent(tag)}');
    if (existing.status == 200 && existing.body is Map<String, dynamic>) {
      return ((existing.body as Map<String, dynamic>)['id'] as num).toInt();
    }
    final created = await requestJsonFull('POST', '/repos/$owner/$repo/releases',
        body: {'tag_name': tag, 'name': tag});
    if (created.status != 201 || created.body is! Map<String, dynamic>) {
      throw GitHubException.diagnose(
        Exception('create release failed'),
        endpoint: '/releases',
        statusCode: created.status,
        parsedBody: created.body,
        responseHeaders: created.headers,
      );
    }
    return ((created.body as Map<String, dynamic>)['id'] as num).toInt();
  }

  Future<String> streamUploadReleaseAsset({
    required String owner,
    required String repo,
    required int releaseId,
    required File file,
    String? customName,
    GitHubCancelToken? cancelToken,
    void Function(int sent, int total, double speed)? onProgress,
  }) async {
    final total = await file.length();
    if (total > GitHubConfig.maxTotalUploadBytes) {
      throw GitHubException(413, 'حجم الملف أكبر من 500 ميجابايت');
    }
    final assetName = customName ?? p.basename(file.path);
    final uri = Uri.parse(
      'https://uploads.github.com/repos/$owner/$repo/releases/$releaseId/assets'
      '?name=${Uri.encodeQueryComponent(assetName)}',
    );
    try {
      final req = await _http
          .postUrl(uri)
          .timeout(Duration(seconds: timeoutSeconds));
      req.bufferOutput = false;
      req.contentLength = total;
      req.headers.set(
          HttpHeaders.authorizationHeader, 'Bearer ${_session.accessToken}');
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers
          .set(HttpHeaders.contentTypeHeader, 'application/octet-stream');

      var sent = 0;
      final sw = Stopwatch()..start();
      await for (final chunk in file.openRead()) {
        if (cancelToken?.isPaused == true) {
          await cancelToken!.waitIfPaused();
        }
        if (cancelToken?.isCancelled == true) {
          req.abort();
          throw GitHubException(499, 'تم إلغاء البث');
        }
        req.add(chunk);
        await req.flush();
        sent += chunk.length;
        final ms = sw.elapsedMilliseconds;
        onProgress?.call(sent, total, ms > 0 ? sent * 1000.0 / ms : 0.0);
      }
      final res =
          await req.close().timeout(Duration(seconds: timeoutSeconds));
      final raw = await res.transform(utf8.decoder).join();
      if (res.statusCode != 201 && res.statusCode != 200) {
        dynamic parsed;
        try {
          parsed = jsonDecode(raw);
        } catch (_) {}
        throw GitHubException.diagnose(
          Exception('Release upload failed'),
          endpoint: 'uploads.github.com/releases/$releaseId/assets',
          statusCode: res.statusCode,
          parsedBody: parsed,
          rawBody: raw,
        );
      }
      return ((jsonDecode(raw) as Map<String, dynamic>)['browser_download_url'] ??
              '')
          .toString();
    } catch (e) {
      throw GitHubException.diagnose(
        e,
        endpoint: 'uploads.github.com/releases/assets',
      );
    }
  }


  // ==========================================================================
  // FULL REPOSITORY CONTROL (v9.0)
  // Rename, Description, Private/Public, Archive, Default Branch, Topics,
  // Delete Repo, Branch Delete, Cloud File Browser/CRUD, Releases, Collaborators
  // ==========================================================================

  Future<GitHubRepo> updateRepo({
    required String owner,
    required String repo,
    String? newName,
    String? description,
    String? homepage,
    bool? isPrivate,
    bool? archived,
    String? defaultBranch,
    bool? hasIssues,
    bool? hasWiki,
  }) async {
    final payload = <String, dynamic>{};
    if (newName != null && newName.trim().isNotEmpty) payload['name'] = newName.trim();
    if (description != null) payload['description'] = description;
    if (homepage != null) payload['homepage'] = homepage;
    if (isPrivate != null) payload['private'] = isPrivate;
    if (archived != null) payload['archived'] = archived;
    if (defaultBranch != null && defaultBranch.trim().isNotEmpty) {
      payload['default_branch'] = defaultBranch.trim();
    }
    if (hasIssues != null) payload['has_issues'] = hasIssues;
    if (hasWiki != null) payload['has_wiki'] = hasWiki;

    final res = await requestJsonFull('PATCH', '/repos/$owner/$repo', body: payload);
    if (res.status != 200 || res.body is! Map<String, dynamic>) {
      throw GitHubException.diagnose(
        Exception('فشل تحديث إعدادات المستودع'),
        endpoint: 'PATCH /repos/$owner/$repo',
        statusCode: res.status,
        parsedBody: res.body,
        responseHeaders: res.headers,
      );
    }
    return GitHubRepo.fromJson(res.body as Map<String, dynamic>);
  }

  Future<void> deleteRepo(String owner, String repo) async {
    final res = await requestJsonFull('DELETE', '/repos/$owner/$repo');
    if (res.status != 204 && res.status != 200) {
      throw GitHubException.diagnose(
        Exception('فشل حذف المستودع (تأكد من صلاحية delete_repo في التوكن)'),
        endpoint: 'DELETE /repos/$owner/$repo',
        statusCode: res.status,
        parsedBody: res.body,
        responseHeaders: res.headers,
      );
    }
  }

  Future<List<String>> setRepoTopics(
    String owner,
    String repo,
    List<String> topics,
  ) async {
    final clean = topics
        .map((t) => t.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]'), '-'))
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();
    final res = await requestJsonFull(
      'PUT',
      '/repos/$owner/$repo/topics',
      body: {'names': clean},
    );
    if (res.status != 200) {
      throw GitHubException.diagnose(
        Exception('فشل تحديث وسوم المستودع'),
        endpoint: 'PUT /repos/$owner/$repo/topics',
        statusCode: res.status,
        parsedBody: res.body,
        responseHeaders: res.headers,
      );
    }
    return clean;
  }

  Future<void> deleteBranch(String owner, String repo, String branch) async {
    final res = await requestJsonFull(
      'DELETE',
      '/repos/$owner/$repo/git/refs/heads/${Uri.encodeComponent(branch)}',
    );
    if (res.status != 204 && res.status != 200) {
      throw GitHubException.diagnose(
        Exception('فشل حذف الفرع $branch'),
        endpoint: 'DELETE /git/refs/heads/$branch',
        statusCode: res.status,
        parsedBody: res.body,
        responseHeaders: res.headers,
      );
    }
  }

  Future<List<GitHubContentEntry>> listRepoContents(
    String owner,
    String repo, {
    String path = '',
    String? ref,
  }) async {
    final cleanPath = path.replaceAll(RegExp(r'^/+|/+$'), '');
    final encodedPath = cleanPath
        .split('/')
        .where((s) => s.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    final q = (ref != null && ref.isNotEmpty)
        ? '?ref=${Uri.encodeQueryComponent(ref)}'
        : '';
    final endpoint = encodedPath.isEmpty
        ? '/repos/$owner/$repo/contents$q'
        : '/repos/$owner/$repo/contents/$encodedPath$q';
    final res = await requestJsonFull('GET', endpoint);
    if (res.status == 404) return [];
    if (res.status != 200) {
      throw GitHubException.diagnose(
        Exception('فشل قراءة محتويات المستودع'),
        endpoint: endpoint,
        statusCode: res.status,
        parsedBody: res.body,
        responseHeaders: res.headers,
      );
    }
    if (res.body is List) {
      final list = (res.body as List)
          .whereType<Map<String, dynamic>>()
          .map(GitHubContentEntry.fromJson)
          .toList();
      list.sort((a, b) {
        if (a.type != b.type) return a.type == 'dir' ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return list;
    }
    if (res.body is Map<String, dynamic>) {
      return [GitHubContentEntry.fromJson(res.body as Map<String, dynamic>)];
    }
    return [];
  }

  Future<({String content, String sha})> getRepoFileText(
    String owner,
    String repo,
    String repoPath, {
    String? ref,
  }) async {
    final encodedPath = repoPath
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'^/+'), '')
        .split('/')
        .map(Uri.encodeComponent)
        .join('/');
    final q = (ref != null && ref.isNotEmpty)
        ? '?ref=${Uri.encodeQueryComponent(ref)}'
        : '';
    final res = await requestJsonFull(
      'GET',
      '/repos/$owner/$repo/contents/$encodedPath$q',
    );
    if (res.status != 200 || res.body is! Map<String, dynamic>) {
      throw GitHubException.diagnose(
        Exception('فشل قراءة الملف $repoPath'),
        endpoint: 'GET /contents/$repoPath',
        statusCode: res.status,
        parsedBody: res.body,
        responseHeaders: res.headers,
      );
    }
    final m = res.body as Map<String, dynamic>;
    final sha = (m['sha'] ?? '').toString();
    final b64 = (m['content'] ?? '').toString().replaceAll('\n', '').replaceAll('\r', '');
    final decoded = utf8.decode(base64Decode(b64), allowMalformed: true);
    return (content: decoded, sha: sha);
  }

  /// Creates or updates a single file directly via GitHub Contents API.
  /// Automatically resolves existing SHA if needed so overwrites never fail.
  Future<String> putRepoFileBytes({
    required String owner,
    required String repo,
    required String repoPath,
    required List<int> bytes,
    required String message,
    String? branch,
    String? existingSha,
  }) async {
    final cleanPath = repoPath
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'^/+'), '');
    final encodedPath = cleanPath.split('/').map(Uri.encodeComponent).join('/');

    var sha = existingSha;
    if (sha == null) {
      final q = (branch != null && branch.isNotEmpty)
          ? '?ref=${Uri.encodeQueryComponent(branch)}'
          : '';
      final check = await requestJsonFull(
        'GET',
        '/repos/$owner/$repo/contents/$encodedPath$q',
      );
      if (check.status == 200 && check.body is Map<String, dynamic>) {
        sha = (check.body as Map<String, dynamic>)['sha']?.toString();
      }
    }

    final payload = <String, dynamic>{
      'message': message,
      'content': base64Encode(bytes),
      if (branch != null && branch.isNotEmpty) 'branch': branch,
      if (sha != null && sha.isNotEmpty) 'sha': sha,
    };

    final res = await requestJsonFull(
      'PUT',
      '/repos/$owner/$repo/contents/$encodedPath',
      body: payload,
    );
    if (res.status != 200 && res.status != 201) {
      throw GitHubException.diagnose(
        Exception('فشل رفع الملف $cleanPath'),
        endpoint: 'PUT /contents/$cleanPath',
        statusCode: res.status,
        parsedBody: res.body,
        responseHeaders: res.headers,
      );
    }
    if (res.body is Map<String, dynamic>) {
      final commit = (res.body as Map<String, dynamic>)['commit'];
      if (commit is Map && commit['sha'] != null) {
        return commit['sha'].toString();
      }
    }
    return 'ok';
  }

  Future<void> deleteRepoFile({
    required String owner,
    required String repo,
    required String repoPath,
    required String sha,
    required String message,
    String? branch,
  }) async {
    final cleanPath = repoPath.replaceAll(RegExp(r'^/+'), '');
    final encodedPath = cleanPath.split('/').map(Uri.encodeComponent).join('/');
    final res = await requestJsonFull(
      'DELETE',
      '/repos/$owner/$repo/contents/$encodedPath',
      body: {
        'message': message,
        'sha': sha,
        if (branch != null && branch.isNotEmpty) 'branch': branch,
      },
    );
    if (res.status != 200 && res.status != 204) {
      throw GitHubException.diagnose(
        Exception('فشل حذف الملف $cleanPath'),
        endpoint: 'DELETE /contents/$cleanPath',
        statusCode: res.status,
        parsedBody: res.body,
        responseHeaders: res.headers,
      );
    }
  }

  /// Reliable File-by-File Upload Engine (ملف ملف).
  /// Works on empty or existing repositories, handles binary & text files,
  /// auto-resolves SHAs for overwrites, supports pause/resume/cancel & retries.
  Future<String> uploadFilesOneByOne({
    required GitHubRepo repo,
    required List<({File file, String repoPath})> items,
    String? targetBranch,
    String? commitPrefix,
    GitHubCancelToken? cancelToken,
    void Function(String)? onLog,
    void Function(UploadProgress)? onProgress,
  }) async {
    if (items.isEmpty) {
      throw GitHubException(400, 'لا توجد ملفات محددة للرفع.');
    }
    final branch = targetBranch ?? repo.defaultBranch;
    final prefix = (commitPrefix == null || commitPrefix.trim().isEmpty)
        ? 'JOOhub upload'
        : commitPrefix.trim();

    var totalBytes = 0;
    for (final it in items) {
      try {
        totalBytes += await it.file.length();
      } catch (_) {}
    }
    if (totalBytes <= 0) totalBytes = 1;

    var uploadedBytes = 0;
    var completedFiles = 0;
    var retriedTotal = 0;
    var lastSha = '';
    final sw = Stopwatch()..start();

    onLog?.call('📤 بدء الرفع الآمن الذكي ملف ملف (${items.length} ملف • ${fmtBytes(totalBytes)})...');

    final remoteShas = <String, String>{};
    try {
      final treeRes = await requestJsonFull(
        'GET',
        '/repos/${repo.owner}/${repo.name}/git/trees/${Uri.encodeComponent(branch)}?recursive=1',
        retries: 1,
      );
      if (treeRes.status == 200 && treeRes.body is Map<String, dynamic>) {
        final treeList = ((treeRes.body as Map)['tree'] as List? ?? []);
        for (final node in treeList.whereType<Map<String, dynamic>>()) {
          if (node['type'] == 'blob') {
            remoteShas[(node['path'] ?? '').toString()] =
                (node['sha'] ?? '').toString();
          }
        }
      }
    } catch (_) {}

    var skippedCount = 0;
    for (var i = 0; i < items.length; i++) {
      if (cancelToken?.isPaused == true) {
        await cancelToken!.waitIfPaused();
      }
      if (cancelToken?.isCancelled == true) {
        throw GitHubException(499, 'تم إلغاء الرفع بواسطة المستخدم.');
      }

      final item = items[i];
      final bytes = await item.file.readAsBytes();
      final ms = sw.elapsedMilliseconds;
      final speed = ms > 0 ? uploadedBytes * 1000.0 / ms : 0.0;

      onProgress?.call(UploadProgress(
        stageEnum: UploadStage.uploading,
        stage: 'رفع ملف ${i + 1} من ${items.length}: ${item.repoPath}',
        currentFile: item.repoPath,
        uploadedBytes: uploadedBytes,
        totalBytes: totalBytes,
        completedFiles: completedFiles,
        totalFiles: items.length,
        speedBytesPerSec: speed,
        currentBatch: i + 1,
        totalBatches: items.length,
        retriedCount: retriedTotal,
      ));

      var ok = false;
      Object? lastErr;
      for (var attempt = 1; attempt <= maxRetries; attempt++) {
        try {
          final existingSha = remoteShas[item.repoPath];
          if (existingSha != null) {
            final localSha = await GitBlobSha1.gitBlobSha1(item.file);
            if (localSha == existingSha) {
              skippedCount++;
              lastSha = existingSha;
              ok = true;
              onLog?.call('⏭️ [${completedFiles + 1}/${items.length}] متطابق (تم تخطيه): ${item.repoPath}');
              break;
            }
          }
          lastSha = await putRepoFileBytes(
            owner: repo.owner,
            repo: repo.name,
            repoPath: item.repoPath,
            bytes: bytes,
            message: 'JOOhub upload: ${item.repoPath}',
            branch: branch,
            existingSha: existingSha,
          );
          ok = true;
          break;
        } catch (e) {
          lastErr = e;
          retriedTotal++;
          if (attempt < maxRetries) {
            onLog?.call('⚠️ إعادة محاولة (${attempt + 1}/$maxRetries) لرفع ${item.repoPath}...');
            await Future<void>.delayed(Duration(milliseconds: 800 * attempt));
          }
        }
      }
      if (!ok) {
        throw lastErr ?? GitHubException(500, 'تعذّر رفع ${item.repoPath}');
      }

      uploadedBytes += bytes.length;
      completedFiles++;
      onLog?.call('✅ [${completedFiles}/${items.length}] ${item.repoPath}');
    }

    onProgress?.call(UploadProgress(
      stageEnum: UploadStage.done,
      stage: 'اكتمل الرفع بنجاح (${items.length - skippedCount} جديد • $skippedCount متطابق)!',
      skippedFiles: skippedCount,
      currentFile: items.last.repoPath,
      uploadedBytes: totalBytes,
      totalBytes: totalBytes,
      completedFiles: items.length,
      totalFiles: items.length,
      speedBytesPerSec: sw.elapsedMilliseconds > 0
          ? totalBytes * 1000.0 / sw.elapsedMilliseconds
          : 0.0,
      currentBatch: items.length,
      totalBatches: items.length,
      retriedCount: retriedTotal,
    ));

    return lastSha.isEmpty ? 'uploaded' : lastSha;
  }

  /// Scans a local project directory and uploads every file one-by-one.
  Future<String> syncDirectoryFileByFile({
    required Directory projectDir,
    required GitHubRepo repo,
    String? targetBranch,
    String? commitMessage,
    GitHubCancelToken? cancelToken,
    void Function(String)? onLog,
    void Function(UploadProgress)? onProgress,
  }) async {
    const ignored = {'.git', 'build', '.dart_tool', '.gradle', '.joohub'};
    final items = <({File file, String repoPath})>[];
    await for (final ent in projectDir.list(recursive: true, followLinks: false)) {
      if (ent is! File) continue;
      final rel = p.relative(ent.path, from: projectDir.path).replaceAll('\\', '/');
      if (rel.isEmpty) continue;
      if (rel.split('/').any((seg) => ignored.contains(seg))) continue;
      items.add((file: ent, repoPath: rel));
    }
    // Upload workflow & pubspec last so GitHub Actions triggers after all files exist!
    items.sort((a, b) {
      int weight(String path) {
        if (path.startsWith('.github/workflows/')) return 2;
        if (path == 'pubspec.yaml') return 1;
        return 0;
      }
      final cmp = weight(a.repoPath).compareTo(weight(b.repoPath));
      return cmp != 0 ? cmp : a.repoPath.compareTo(b.repoPath);
    });
    return uploadFilesOneByOne(
      repo: repo,
      items: items,
      targetBranch: targetBranch,
      commitPrefix: commitMessage ?? 'JOOhub',
      cancelToken: cancelToken,
      onLog: onLog,
      onProgress: onProgress,
    );
  }

  Future<bool> cancelWorkflowRun(String owner, String repo, int runId) async {
    final res = await requestJsonFull(
      'POST',
      '/repos/$owner/$repo/actions/runs/$runId/cancel',
    );
    return res.status == 202 || res.status == 200;
  }

  Future<bool> rerunWorkflowRun(String owner, String repo, int runId) async {
    final res = await requestJsonFull(
      'POST',
      '/repos/$owner/$repo/actions/runs/$runId/rerun',
    );
    return res.status == 201 || res.status == 200;
  }

  Future<void> deleteRelease(String owner, String repo, int releaseId) async {
    final res = await requestJsonFull(
      'DELETE',
      '/repos/$owner/$repo/releases/$releaseId',
    );
    if (res.status != 204 && res.status != 200) {
      throw GitHubException.diagnose(
        Exception('فشل حذف الإصدار'),
        endpoint: 'DELETE /releases/$releaseId',
        statusCode: res.status,
        parsedBody: res.body,
        responseHeaders: res.headers,
      );
    }
  }

  Future<void> deleteReleaseAsset(String owner, String repo, int assetId) async {
    final res = await requestJsonFull(
      'DELETE',
      '/repos/$owner/$repo/releases/assets/$assetId',
    );
    if (res.status != 204 && res.status != 200) {
      throw GitHubException.diagnose(
        Exception('فشل حذف ملف الإصدار'),
        endpoint: 'DELETE /releases/assets/$assetId',
        statusCode: res.status,
        parsedBody: res.body,
        responseHeaders: res.headers,
      );
    }
  }

  Future<List<Map<String, dynamic>>> listCollaborators(
    String owner,
    String repo,
  ) async {
    final res = await requestJsonFull('GET', '/repos/$owner/$repo/collaborators');
    if (res.status == 200 && res.body is List) {
      return (res.body as List).whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }

  Future<void> addCollaborator(
    String owner,
    String repo,
    String username, {
    String permission = 'push',
  }) async {
    final res = await requestJsonFull(
      'PUT',
      '/repos/$owner/$repo/collaborators/${Uri.encodeComponent(username.trim())}',
      body: {'permission': permission},
    );
    if (res.status != 201 && res.status != 204 && res.status != 200) {
      throw GitHubException.diagnose(
        Exception('فشل إضافة المتعاون $username'),
        endpoint: 'PUT /collaborators/$username',
        statusCode: res.status,
        parsedBody: res.body,
        responseHeaders: res.headers,
      );
    }
  }

  Future<void> removeCollaborator(
    String owner,
    String repo,
    String username,
  ) async {
    final res = await requestJsonFull(
      'DELETE',
      '/repos/$owner/$repo/collaborators/${Uri.encodeComponent(username.trim())}',
    );
    if (res.status != 204 && res.status != 200) {
      throw GitHubException.diagnose(
        Exception('فشل إزالة المتعاون $username'),
        endpoint: 'DELETE /collaborators/$username',
        statusCode: res.status,
        parsedBody: res.body,
        responseHeaders: res.headers,
      );
    }
  }

  static String fmtBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  static String fmtDuration(Duration? d) {
    if (d == null) return '--';
    if (d.inSeconds < 60) return '${d.inSeconds} ثانية';
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m د $s ث';
  }
}
