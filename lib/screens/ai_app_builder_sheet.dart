import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../services/ai_engine.dart';
import '../services/workspace_manager.dart';

// ============================================================================
// AI APP BUILDER SETUP SHEET
// App Name + Package Name + App Icon + 6 Interactive Customization Choices
// ============================================================================

class AiAppBuilderSheet extends StatefulWidget {
  final String initialPrompt;
  const AiAppBuilderSheet({super.key, required this.initialPrompt});

  @override
  State<AiAppBuilderSheet> createState() => _AiAppBuilderSheetState();
}

class _AiAppBuilderSheetState extends State<AiAppBuilderSheet> {
  late final TextEditingController _promptCtrl;
  final _nameCtrl = TextEditingController();
  final _pkgCtrl = TextEditingController();
  bool _pkgManuallyEdited = false;
  String? _iconPath;

  // 6 User Choices (exceeding minimum of 5)
  String _category = 'أدوات وإنتاجية';
  String _visualStyle = 'داكن صلب (Obsidian)';
  int _accentIdx = 0;
  String _language = 'عربي كامل (RTL)';
  String _navigation = 'شريط سفلي (تبويبات)';
  final Set<String> _features = {
    'تخزين محلي',
    'بحث وفلترة',
    'بناء APK تلقائي',
  };

  static const List<String> _categories = [
    'أدوات وإنتاجية',
    'متجر وتجارة',
    'محادثة وتواصل',
    'إدارة ومالية',
    'تعليم ومحتوى',
    'مخصص',
  ];

  static const List<String> _styles = [
    'داكن صلب (Obsidian)',
    'فاتح نظيف (Light)',
    'زجاجي حديث (Glass)',
    'Material 3',
    'تقني داكن (Carbon)',
  ];

  static const List<(String, String, Color)> _accents = [
    ('برتقالي', '#FF6B00', Color(0xFFFF6B00)),
    ('أزرق', '#3B82F6', Color(0xFF3B82F6)),
    ('أخضر', '#22C55E', Color(0xFF22C55E)),
    ('أحمر', '#EF4444', Color(0xFFEF4444)),
    ('بنفسجي', '#8B5CF6', Color(0xFF8B5CF6)),
    ('ذهبي', '#F59E0B', Color(0xFFF59E0B)),
  ];

  static const List<String> _languages = [
    'عربي كامل (RTL)',
    'إنجليزي (LTR)',
    'ثنائي اللغة (AR + EN)',
  ];

  static const List<String> _navigations = [
    'شريط سفلي (تبويبات)',
    'قائمة جانبية (Drawer)',
    'رئيسية + صفحات فرعية',
    'لوحة تحكم شاملة',
  ];

  static const List<String> _featureOptions = [
    'تخزين محلي',
    'بحث وفلترة',
    'شاشة إعدادات',
    'تصدير ومشاركة',
    'اتصال API',
    'بناء APK تلقائي',
  ];

  @override
  void initState() {
    super.initState();
    _promptCtrl = TextEditingController(text: widget.initialPrompt.trim());
    _nameCtrl.addListener(_syncPackage);
  }

  void _syncPackage() {
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
      if (x != null && mounted) setState(() => _iconPath = x.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر اختيار الصورة: $e')),
        );
      }
    }
  }

  void _submit() {
    final prompt = _promptCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final pkg = _pkgCtrl.text.trim();

    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب وصف التطبيق المطلوب بناؤه')),
      );
      return;
    }
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل اسم التطبيق أولاً')),
      );
      return;
    }
    if (!WorkspaceManager.isValidPackageName(pkg)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('صيغة Package Name غير صالحة (مثال: com.yossefjoo.app)'),
        ),
      );
      return;
    }

    final acc = _accents[_accentIdx];
    Navigator.of(context).pop(
      AiBuildSpec(
        prompt: prompt,
        appName: name,
        packageName: pkg,
        iconPath: _iconPath,
        category: _category,
        visualStyle: _visualStyle,
        accentName: acc.$1,
        accentHex: acc.$2,
        language: _language,
        navigation: _navigation,
        features: _features.toList(),
      ),
    );
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    _nameCtrl.dispose();
    _pkgCtrl.dispose();
    super.dispose();
  }

  Widget _sectionLabel(String number, String title, Color accent) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: accent.withValues(alpha: 0.4)),
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _singleChoiceWrap({
    required List<String> options,
    required String selected,
    required Color accent,
    required ValueChanged<String> onSelect,
  }) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: options.map((opt) {
        final isSel = opt == selected;
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onSelect(opt),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: isSel ? accent.withValues(alpha: 0.18) : kSurfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSel ? accent : kStroke,
                width: isSel ? 1.2 : 1,
              ),
            ),
            child: Text(
              opt,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                color: isSel ? Colors.white : Colors.white70,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = appState.primaryColor;
    final pkgValid = _pkgCtrl.text.trim().isNotEmpty &&
        WorkspaceManager.isValidPackageName(_pkgCtrl.text);

    return DraggableScrollableSheet(
      initialChildSize: 0.90,
      minChildSize: 0.65,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollCtrl) {
        return Container(
          decoration: const BoxDecoration(
            color: kBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            border: Border(top: BorderSide(color: kStroke)),
          ),
          child: Column(
            children: [
              // Drag Handle & Header
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                child: Column(
                  children: [
                    Container(
                      width: 36,
                      height: 3.5,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.auto_awesome_rounded,
                            color: accent, size: 18),
                        const SizedBox(width: 7),
                        const Expanded(
                          child: Text(
                            'تجهيز بناء التطبيق بالذكاء الاصطناعي',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.close_rounded,
                              size: 19, color: Colors.white60),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: kStroke),

              // Body
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.all(14),
                  children: [
                    // App Prompt
                    TextField(
                      controller: _promptCtrl,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 12.5),
                      decoration: const InputDecoration(
                        labelText: 'فكرة التطبيق المطلوب',
                        hintText: 'اشرح ما تريد بناءه بدقة...',
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Identity: Icon + Name + Package
                    ApexCard(
                      borderColor: accent.withValues(alpha: 0.35),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              GestureDetector(
                                onTap: _pickIcon,
                                child: Container(
                                  width: 54,
                                  height: 54,
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: accent.withValues(alpha: 0.45),
                                    ),
                                    image: _iconPath != null
                                        ? DecorationImage(
                                            image: FileImage(File(_iconPath!)),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  child: _iconPath == null
                                      ? Icon(Icons.add_a_photo_outlined,
                                          color: accent, size: 22)
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _nameCtrl,
                                  style: const TextStyle(fontSize: 12.5),
                                  decoration: const InputDecoration(
                                    labelText: 'اسم التطبيق (App Name)',
                                    hintText: 'مثال: Smart Tasks',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _pkgCtrl,
                            onChanged: (_) {
                              _pkgManuallyEdited = true;
                              setState(() {});
                            },
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11.5,
                            ),
                            decoration: InputDecoration(
                              labelText: 'اسم الحزمة (Package Name)',
                              hintText: 'com.yossefjoo.myapp',
                              suffixIcon: Icon(
                                pkgValid
                                    ? Icons.check_circle_rounded
                                    : Icons.info_outline_rounded,
                                size: 17,
                                color: pkgValid ? kSuccess : Colors.white38,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              ActionChipBtn(
                                icon: Icons.photo_library_outlined,
                                label: _iconPath == null
                                    ? 'اختيار صورة للأيقونة'
                                    : 'تغيير الصورة',
                                color: accent,
                                onTap: _pickIcon,
                              ),
                              if (_iconPath != null) ...[
                                const SizedBox(width: 6),
                                ActionChipBtn(
                                  icon: Icons.close_rounded,
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

                    const SizedBox(height: 12),

                    // Choice 1: Category
                    ApexCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionLabel('1', 'نوع وفئة التطبيق', accent),
                          _singleChoiceWrap(
                            options: _categories,
                            selected: _category,
                            accent: accent,
                            onSelect: (v) => setState(() => _category = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Choice 2: Visual Style
                    ApexCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionLabel('2', 'الأسلوب البصري والثيم', accent),
                          _singleChoiceWrap(
                            options: _styles,
                            selected: _visualStyle,
                            accent: accent,
                            onSelect: (v) => setState(() => _visualStyle = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Choice 3: Accent Color
                    ApexCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionLabel('3', 'اللون الأساسي للتطبيق', accent),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: List.generate(_accents.length, (i) {
                              final item = _accents[i];
                              final sel = i == _accentIdx;
                              return InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => setState(() => _accentIdx = i),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 9, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: sel
                                        ? item.$3.withValues(alpha: 0.18)
                                        : kSurfaceAlt,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: sel ? item.$3 : kStroke,
                                      width: sel ? 1.2 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: item.$3,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        item.$1,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: sel
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                          color: sel
                                              ? Colors.white
                                              : Colors.white70,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Choice 4: Language & Direction
                    ApexCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionLabel('4', 'اللغة واتجاه الواجهة', accent),
                          _singleChoiceWrap(
                            options: _languages,
                            selected: _language,
                            accent: accent,
                            onSelect: (v) => setState(() => _language = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Choice 5: Navigation Structure
                    ApexCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionLabel('5', 'هيكل التنقل والصفحات', accent),
                          _singleChoiceWrap(
                            options: _navigations,
                            selected: _navigation,
                            accent: accent,
                            onSelect: (v) => setState(() => _navigation = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Choice 6: Extra Features (Multi-Select)
                    ApexCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionLabel('6', 'الميزات والقدرات الإضافية', accent),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _featureOptions.map((feat) {
                              final on = _features.contains(feat);
                              return InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  setState(() {
                                    if (on) {
                                      _features.remove(feat);
                                    } else {
                                      _features.add(feat);
                                    }
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 9, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: on
                                        ? accent.withValues(alpha: 0.16)
                                        : kSurfaceAlt,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: on ? accent : kStroke,
                                      width: on ? 1.2 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        on
                                            ? Icons.check_box_rounded
                                            : Icons.check_box_outline_blank_rounded,
                                        size: 13,
                                        color: on ? accent : Colors.white38,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        feat,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: on
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                          color: on
                                              ? Colors.white
                                              : Colors.white70,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),

              // Sticky Bottom CTA
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                decoration: const BoxDecoration(
                  color: kSurface,
                  border: Border(top: BorderSide(color: kStroke)),
                ),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.rocket_launch_rounded, size: 17),
                      label: const Text('ابدأ البناء الكامل الآن'),
                      onPressed: _submit,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
