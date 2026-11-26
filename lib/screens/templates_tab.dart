import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../services/workspace_manager.dart';
import 'create_project_wizard.dart';

// ============================================================================
// TAB 4 — 8 PRO TEMPLATES GALLERY (OPENS APP CREATION WIZARD)
// ============================================================================

class TemplatesGalleryTab extends StatelessWidget {
  final VoidCallback onCreated;
  const TemplatesGalleryTab({super.key, required this.onCreated});

  @override
  Widget build(BuildContext context) {
    final accent = appState.primaryColor;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'مكتبة القوالب الجاهزة',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              ApexPill(text: '${kTemplates.length} قوالب', color: accent),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'اضغط على أي قالب لاختيار اسم التطبيق، اسم الباكدج، والأيقونة وإنشائه فوراً',
            style: TextStyle(fontSize: 12, color: Colors.white60),
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.92,
            ),
            itemCount: kTemplates.length,
            itemBuilder: (context, i) {
              final t = kTemplates[i];
              return ApexCard(
                onTap: () async {
                  final proj = await Navigator.of(context).push<LocalProject>(
                    MaterialPageRoute(
                      builder: (_) =>
                          CreateProjectWizardScreen(initialTemplate: t),
                    ),
                  );
                  if (proj != null) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text('تم إنشاء تطبيق «${proj.name}» بنجاح')),
                      );
                    }
                    onCreated();
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: t.color.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(t.icon, color: t.color),
                    ),
                    const Spacer(),
                    Text(
                      t.title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.white60),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
