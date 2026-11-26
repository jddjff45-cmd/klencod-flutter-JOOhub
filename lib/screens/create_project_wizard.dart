import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../services/workspace_manager.dart';

// ============================================================================
// CREATE NEW APP WIZARD — APP NAME + PACKAGE NAME + APP ICON + TEMPLATE + PERMS
// ============================================================================

class CreateProjectWizardScreen extends StatefulWidget {
  final ProjectTemplate? initialTemplate;
  const CreateProjectWizardScreen({super.key, this.initialTemplate});

  @override
  State<CreateProjectWizardScreen> createState() =>
      _CreateProjectWizardScreenState();
}

class _CreateProjectWizardScreenState extends State<CreateProjectWizardScreen> {
  final _nameCtrl = TextEditingController();
  final _pkgCtrl = TextEditingController(text: 'com.yossefjoo.myapp');
  final _verCtrl = TextEditingController(text: '1.0.0');
  final _buildCtrl = TextEditingController(text: '1');

  bool _pkgManuallyEdited = false;
  String? _iconPath;
  late ProjectTemplate _selectedTemplate;
  bool _injectApkWorkflow = true;
  bool _creating = false;

  final Set<String> _selectedPerms = {
    'android.permission.INTERNET',
    'android.permission.ACCESS_NETWORK_STATE',
  };

  @override
  void initState() {
    super.initState();
    _selectedTemplate = widget.initialTemplate ?? kTemplates.first;
    _nameCtrl.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    if (!_pkgManuallyEdited) {
      final suggested = WorkspaceManager.suggestPackageName(_nameCtrl.text);
      _pkgCtrl.value = TextEditingValue(
        text: suggested,
        selection: TextSelection.collapsed(offset: suggested.length),
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickIcon() async {
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (x != null && mounted) {
        setState(() => _iconPath = x.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر اختيار الصورة: $e')),
        );
      }
    }
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    final pkg = _pkgCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال اسم التطبيق أولاً')),
      );
      return;
    }
    if (!WorkspaceManager.isValidPackageName(pkg)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'صيغة Package Name غير صحيحة — مثال صحيح: com.yossefjoo.myapp',
          ),
        ),
      );
      return;
    }

    setState(() => _creating = true);
    try {
      final proj = await WorkspaceManager.createProject(
        name,
        packageName: pkg,
        iconSourcePath: _iconPath,
        version: _verCtrl.text.trim().isEmpty ? '1.0.0' : _verCtrl.text.trim(),
        buildNumber:
            _buildCtrl.text.trim().isEmpty ? '1' : _buildCtrl.text.trim(),
        template: _selectedTemplate,
        permissions: _selectedPerms.toList(),
        injectApkWorkflow: _injectApkWorkflow,
      );
      appState.setActiveProject(proj);
      if (mounted) Navigator.of(context).pop(proj);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء الإنشاء: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pkgCtrl.dispose();
    _verCtrl.dispose();
    _buildCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = appState.primaryColor;
    final pkgValid = WorkspaceManager.isValidPackageName(_pkgCtrl.text);

    return Scaffold(
      appBar: AppBar(
        title: const Text('إنشاء تطبيق جديد'),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: ApexPill(text: 'مشروع جديد', color: accent),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // 1. App Icon Picker Card
          ApexCard(
            borderColor: accent.withValues(alpha: 0.4),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _pickIcon,
                  child: Stack(
                    children: [
                      Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.55),
                            width: 1.5,
                          ),
                          image: _iconPath != null
                              ? DecorationImage(
                                  image: FileImage(File(_iconPath!)),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: _iconPath == null
                            ? Icon(
                                Icons.add_photo_alternate_rounded,
                                color: accent,
                                size: 32,
                              )
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.edit,
                            size: 13,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'صورة / أيقونة التطبيق',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _iconPath != null
                            ? 'تم اختيار الأيقونة — سيتم حقنها تلقائياً في جميع مقاسات أندرويد (mipmap)'
                            : 'اضغط لاختيار صورة التطبيق من المعرض (PNG / JPG)',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Colors.white60,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ActionChipBtn(
                            icon: Icons.photo_library_outlined,
                            label: _iconPath == null ? 'اختيار صورة' : 'تغيير',
                            color: accent,
                            onTap: _pickIcon,
                          ),
                          if (_iconPath != null) ...[
                            const SizedBox(width: 8),
                            ActionChipBtn(
                              icon: Icons.delete_outline,
                              label: 'إزالة',
                              color: kCoral,
                              onTap: () => setState(() => _iconPath = null),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 2. App Name + Package Name + Version
          ApexCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.badge_outlined, color: accent, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'هوية التطبيق الأساسية',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'اسم التطبيق (App Name)',
                    hintText: 'مثال: JOO Store Pro',
                    prefixIcon: Icon(Icons.apps_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pkgCtrl,
                  onChanged: (_) {
                    _pkgManuallyEdited = true;
                    setState(() {});
                  },
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'اسم الباكدج (Package Name)',
                    hintText: 'com.yossefjoo.myapp',
                    prefixIcon: const Icon(Icons.fingerprint_rounded),
                    suffixIcon: Icon(
                      pkgValid ? Icons.check_circle : Icons.error_outline,
                      color: pkgValid ? kSuccess : kCoral,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  pkgValid
                      ? '✓ اسم الباكدج صالح وجاهز لبناء APK'
                      : 'يجب أن يتكون من مقطعين على الأقل بحروف إنجليزية صغيرة (مثال: com.company.app)',
                  style: TextStyle(
                    fontSize: 11,
                    color: pkgValid ? kSuccess : kCoral,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _verCtrl,
                        decoration: const InputDecoration(
                          labelText: 'الإصدار (Version)',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _buildCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'رقم البناء (Build)',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 3. Starter Template Horizontal Selector
          ApexCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome_mosaic, color: accent, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'قالب البداية',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 86,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: kTemplates.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final t = kTemplates[i];
                      final sel = t.id == _selectedTemplate.id;
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => setState(() => _selectedTemplate = t),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 140,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: sel
                                ? accent.withValues(alpha: 0.16)
                                : kSurfaceAlt,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: sel ? accent : kStroke,
                              width: sel ? 1.5 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Icon(t.icon,
                                  size: 20, color: sel ? accent : t.color),
                              Text(
                                t.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: sel ? Colors.white : Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 4. Android Permissions & Auto APK Workflow
          ApexCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.shield_outlined, color: accent, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'صلاحيات أندرويد وبناء APK',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: kAndroidPermissions.take(7).map((perm) {
                    final on = _selectedPerms.contains(perm.permission);
                    return FilterChip(
                      selected: on,
                      selectedColor: accent.withValues(alpha: 0.22),
                      checkmarkColor: accent,
                      backgroundColor: kSurfaceAlt,
                      side: BorderSide(color: on ? accent : kStroke),
                      label: Text(
                        perm.label,
                        style: const TextStyle(fontSize: 11),
                      ),
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _selectedPerms.add(perm.permission);
                          } else {
                            _selectedPerms.remove(perm.permission);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const Divider(height: 22, color: kStroke),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: accent,
                  title: const Text(
                    'حقن ملف بناء APK السحابي تلقائياً',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text(
                    'يضيف .github/workflows/joohub_build_apk.yml جاهزاً لبناء Release APK فور الرفع',
                    style: TextStyle(fontSize: 11, color: Colors.white60),
                  ),
                  value: _injectApkWorkflow,
                  onChanged: (v) => setState(() => _injectApkWorkflow = v),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          FilledButton.icon(
            icon: _creating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const Icon(Icons.rocket_launch_rounded),
            label: Text(_creating ? 'جاري إنشاء التطبيق...' : 'إنشاء التطبيق الآن'),
            onPressed: _creating ? null : _create,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
