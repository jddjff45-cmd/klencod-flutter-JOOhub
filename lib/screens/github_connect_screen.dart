import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../services/github_engine.dart';
import 'network_doctor_screen.dart';

// ============================================================================
// GITHUB CONNECT SCREEN v7.0 — EGYPTIAN ARABIC + RESILIENT DIAGNOSTICS
// ============================================================================

class GitHubConnectScreen extends StatefulWidget {
  const GitHubConnectScreen({super.key});
  @override
  State<GitHubConnectScreen> createState() => _GitHubConnectScreenState();
}

class _GitHubConnectScreenState extends State<GitHubConnectScreen> {
  final _patCtrl = TextEditingController();
  GitHubDeviceCode? _device;
  GitHubCancelToken? _cancel;
  GitHubApiClient? _api;
  bool _busy = false;
  String? _status;
  GitHubException? _error;

  Future<void> _startDeviceOAuth() async {
    setState(() {
      _busy = true;
      _error = null;
      _status = 'بنفحص الاتصال بسيرفرات GitHub...';
    });

    _cancel?.cancel();
    _cancel = GitHubCancelToken();
    _api?.close();
    _api = GitHubApiClient(
      '',
      maxRetries: appState.maxRetries,
      timeoutSeconds: appState.timeoutSeconds,
    );

    try {
      final health = await _api!.checkConnectionHealth();
      if (!health.dnsOk) {
        throw health.error ??
            GitHubException(-1, 'مفيش اتصال بـ GitHub حالياً');
      }

      final code =
          await _api!.startDeviceFlow(clientId: GitHubConfig.oauthClientId);
      if (!mounted) return;
      setState(() {
        _device = code;
        _status =
            'تمام! عملنالك كود الربط ونسخناه تلقائي — افتح صفحة GitHub وحط الكود ووافق.';
      });
      await Clipboard.setData(ClipboardData(text: code.userCode));

      final session = await _api!.pollDeviceFlowSession(
        clientId: GitHubConfig.oauthClientId,
        code: code,
        cancelToken: _cancel,
      );
      final user = await _api!.verifyUser();
      await appState.upsertAccount(GitHubAccount(
        login: user.login,
        name: user.name,
        session: session,
      ));
      await appState.recordActivity(
        'ربط حساب GitHub',
        'تم ربط الحساب @${user.login} بنجاح عن طريق Device OAuth',
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      final diag = GitHubException.diagnose(e, endpoint: 'Device OAuth');
      await appState.recordActivity(
        'فشل ربط حساب GitHub',
        '${diag.title} — ${diag.reason}',
        isError: true,
      );
      if (!mounted) return;
      setState(() {
        _error = diag;
        _status = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connectPat() async {
    final token = _patCtrl.text.trim();
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب التوكن الأول عشان نتأكد منه')),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = 'بنتأكد من التوكن وصلاحياته...';
    });
    final client = GitHubApiClient(
      token,
      maxRetries: appState.maxRetries,
      timeoutSeconds: appState.timeoutSeconds,
    );
    try {
      final user = await client.verifyUser();
      await appState.upsertAccount(GitHubAccount(
        login: user.login,
        name: user.name,
        session: GitHubAuthSession(accessToken: token),
      ));
      await appState.recordActivity(
        'ربط حساب GitHub (PAT)',
        'تم ربط الحساب @${user.login} بالتوكن الشخصي بنجاح',
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      final diag = GitHubException.diagnose(e, endpoint: 'PAT /user');
      await appState.recordActivity(
        'فشل التحقق من التوكن',
        '${diag.title} — ${diag.reason}',
        isError: true,
      );
      if (mounted) {
        setState(() {
          _error = diag;
          _status = null;
        });
      }
    } finally {
      client.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openVerification(String url) async {
    final uri = Uri.parse(url);
    final mode = appState.browserMode;
    if (mode == BrowserOpenMode.inApp) {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      return;
    }
    if (mode == BrowserOpenMode.external) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    final choice = await showModalBottomSheet<LaunchMode>(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  Icon(Icons.open_in_browser, color: appState.primaryColor),
              title: const Text('افتح جوه التطبيق'),
              onTap: () => Navigator.pop(context, LaunchMode.inAppBrowserView),
            ),
            ListTile(
              leading: const Icon(Icons.public, color: kSky),
              title: const Text('افتح في المتصفح الخارجي'),
              onTap: () =>
                  Navigator.pop(context, LaunchMode.externalApplication),
            ),
          ],
        ),
      ),
    );
    if (choice != null) await launchUrl(uri, mode: choice);
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _api?.close();
    _patCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = appState.primaryColor;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ربط حسابك على GitHub'),
        actions: [
          IconButton(
            tooltip: 'فحص الشبكة',
            icon: Icon(Icons.network_check_rounded, color: accent),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NetworkDoctorScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ApexCard(
            borderColor: accent.withValues(alpha: 0.45),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.verified_user_rounded, size: 42, color: accent),
                const SizedBox(height: 10),
                const Text(
                  'ربط سريع وآمن عبر GitHub OAuth',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text(
                  'بيسمحلك ترفع مشاريعك على مراحل حتى 500MB، تبني APK سحابي على GitHub Actions، وتحمّل الإصدارات بضغطة واحدة.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: Colors.white60),
                ),
                const SizedBox(height: 14),
                if (_device != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: kSurfaceAlt,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: accent),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'كود التفعيل (اتنسخ تلقائي في الحافظة):',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          _device!.userCode,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 4,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('افتح صفحة التفعيل على GitHub'),
                    onPressed: () =>
                        _openVerification(_device!.verificationUri),
                  ),
                ] else
                  FilledButton.icon(
                    icon: const Icon(Icons.login_rounded),
                    label: Text(_busy ? 'بنتصل بـ GitHub...' : 'ابدأ الربط السريع'),
                    onPressed: _busy ? null : _startDeviceOAuth,
                  ),
              ],
            ),
          ),

          if (_status != null) ...[
            const SizedBox(height: 12),
            ApexCard(
              borderColor: accent,
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _status!,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_error != null) ...[
            const SizedBox(height: 12),
            ErrorDiagnosticCard(
              error: _error!,
              onRetry: _startDeviceOAuth,
              onDismiss: () => setState(() => _error = null),
            ),
          ],

          const SizedBox(height: 16),
          ApexCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'أو اربط بالتوكن الشخصي (Personal Access Token)',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text(
                  'اتأكد إن التوكن واخد صلاحية repo و workflow عشان الرفع وبناء APK يشتغلوا تمام.',
                  style: TextStyle(fontSize: 11.5, color: Colors.white54),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _patCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'حط التوكن هنا (ghp_xxxx...)',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _busy ? null : _connectPat,
                  child: const Text('تأكيد وربط التوكن'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
