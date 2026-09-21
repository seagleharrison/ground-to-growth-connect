import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/biometric_auth.dart';
import '../services/document_scanner_service.dart';
import '../theme/app_theme.dart';
import 'resources_view.dart' show DocumentGuidesView;
import '../widgets/confetti.dart';
import '../widgets/ui.dart';

/// Direct equivalent of the native app's DocumentsView.swift: consent gate,
/// checklist of core document types, step-up Face ID before scanning or
/// viewing, and a 3-step upload wizard.
class DocumentsView extends StatefulWidget {
  const DocumentsView({super.key});

  @override
  State<DocumentsView> createState() => _DocumentsViewState();
}

class _DocumentsViewState extends State<DocumentsView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().refreshDocumentConsent();
    });
  }

  Future<void> _authenticateThenRun(String reason, VoidCallback action) async {
    final ok = await BiometricAuth.authenticate(reason);
    if (!mounted) return;
    if (ok) {
      action();
    } else {
      context.read<AppState>().reportError('Authentication failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final granted = app.documentConsent?.granted == true;

    return LargeTitlePage(
      title: 'Documents',
      onRefresh: () => context.read<AppState>().refreshDocumentConsent(),
      children: granted ? _documentsChildren(context, app) : _consentGateChildren(context, app),
    );
  }

  /// Opens the upload walkthrough after a fresh Face ID/passcode check. With
  /// [startAt] it jumps straight to scanning that document type.
  void _openWizard({DocumentType? startAt}) {
    _authenticateThenRun(
      "Verify it's you before adding a document",
      () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => UploadDocumentSheet(initialType: startAt),
          fullscreenDialog: true,
        ),
      ),
    );
  }

  List<Widget> _documentsChildren(BuildContext context, AppState app) {
    final missing = missingCoreDocuments(app.documents, hidden: app.hiddenDocuments);
    final checklistSize = app.documentChecklist.length;
    return [
      const FadeSlideIn(
        child: Padding(
          padding: EdgeInsets.only(left: 4, right: 4, bottom: 18),
          child: Text(
            'Your important papers: encrypted, private, and always with you.',
            style: TextStyle(color: Colors.white60, fontSize: 15, height: 1.4),
          ),
        ),
      ),
      FadeSlideIn(delay: const Duration(milliseconds: 80), child: _checklistCard(context, app)),
      const SizedBox(height: 20),
      if (missing.isNotEmpty) ...[
        GradientButton(
          icon: Icons.document_scanner_rounded,
          label: missing.length == checklistSize
              ? 'Start: ${missing.first.label}'
              : 'Next: ${missing.first.label}',
          onPressed: () => _openWizard(startAt: missing.first),
        ),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: () => _openWizard(), child: const Text('Add a different document')),
      ] else ...[
        AppCard(
          color: const Color(0xFF14261A),
          padding: const EdgeInsets.all(16),
          child: const Row(
            children: [
              Icon(Icons.verified_rounded, color: walletGreen, size: 28),
              SizedBox(width: 12),
              Expanded(child: Text("Everything on your list is on file. You're all set.", style: TextStyle(fontWeight: FontWeight.w600, height: 1.35))),
            ],
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: () => _openWizard(), child: const Text('Add another document')),
      ],
      const SizedBox(height: 16),
      AppCard(
        key: const Key('replace-guides-card'),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DocumentGuidesView())),
        child: const Row(
          children: [
            Icon(Icons.find_replace_rounded, color: Brand.orange),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Lost a document?', style: TextStyle(fontWeight: FontWeight.w700)),
                  SizedBox(height: 2),
                  Text('See how to replace it, step by step', style: TextStyle(color: Colors.white54, fontSize: 13)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.white38),
          ],
        ),
      ),
      if (app.documents.isNotEmpty) ...[
        const SizedBox(height: 28),
        const SectionLabel('All documents'),
        for (final doc in app.documents)
          _documentRow(
            context,
            doc,
            onTap: () => _authenticateThenRun(
              "Verify it's you before viewing this document",
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DocumentDetailView(document: doc))),
            ),
          ),
      ],
      const SizedBox(height: 28),
      OutlinedButton(
        onPressed: () => context.read<AppState>().revokeDocumentConsent(),
        style: OutlinedButton.styleFrom(foregroundColor: Brand.red),
        child: const Text('Stop storing documents'),
      ),
      const SizedBox(height: 10),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          'This does not delete documents already stored — delete those individually. '
          'It only stops you from uploading new ones until you opt back in.',
          style: TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.4),
        ),
      ),
    ];
  }

  /// The three core documents as a stack of wallet cards, like Apple Wallet:
  /// each card peeks out from behind the next. A green check in a circle on
  /// the right means it's on file; an empty circle means it's still needed.
  /// Tapping a card adds that document, or opens it if it's already on file.
  Widget _checklistCard(BuildContext context, AppState app) {
    final checklist = app.documentChecklist;
    final total = checklist.length;
    final done = total - missingCoreDocuments(app.documents, hidden: app.hiddenDocuments).length;

    const cardHeight = 176.0;
    const peek = 96.0; // how much of each card shows above the next one
    final stackHeight = total == 0 ? 0.0 : peek * (total - 1) + cardHeight;
    final hidden = [for (final t in DocumentType.coreChecklist) if (!checklist.contains(t)) t];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Your documents', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            Text(
              total == 0 ? 'Nothing left on your list' : '$done of $total on file',
              style: TextStyle(color: total > 0 && done == total ? walletGreen : Colors.grey, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: stackHeight,
          child: Stack(
            children: [
              for (final (index, type) in checklist.indexed)
                Positioned(
                  top: index * peek,
                  left: 0,
                  right: 0,
                  height: cardHeight,
                  child: _walletCard(context, app, type),
                ),
            ],
          ),
        ),
        if (hidden.isNotEmpty) ...[
          const SizedBox(height: 16),
          _hiddenDocuments(app, hidden),
        ],
      ],
    );
  }

  /// The documents the person said they don't have, each with a way back.
  Widget _hiddenDocuments(AppState app, List<DocumentType> hidden) {
    return AppCard(
      key: const Key('hidden-documents'),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Hidden — you said you don\'t have these', style: TextStyle(color: Colors.white60, fontSize: 13)),
          for (final type in hidden)
            Row(
              children: [
                Icon(walletIcon(type), size: 20, color: Colors.white54),
                const SizedBox(width: 12),
                Expanded(child: Text(type.label, style: const TextStyle(color: Colors.white70, fontSize: 15))),
                TextButton(
                  key: Key('unhide-${type.wireValue}'),
                  onPressed: () => app.unhideDocument(type),
                  child: const Text('Show again', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _walletCard(BuildContext context, AppState app, DocumentType type) {
    final docs = app.documents.where((d) => d.type == type).toList();
    final onFile = docs.isNotEmpty;
    final colors = walletColors(type);

    return PressableScale(
      key: Key('wallet-card-${type.wireValue}'),
      pressedScale: 0.985,
      onTap: () {
        if (!onFile) {
          _openWizard(startAt: type);
        } else {
          _authenticateThenRun(
            "Verify it's you before viewing this document",
            () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => DocumentDetailView(document: docs.first)),
            ),
          );
        }
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          boxShadow: const [
            // Shadow falls upward so the card below visibly sits on top of
            // the one above it, the way wallet cards do.
            BoxShadow(color: Colors.black54, blurRadius: 14, offset: Offset(0, -3)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              right: -14,
              bottom: -18,
              child: Icon(walletIcon(type), size: 120, color: Colors.white.withValues(alpha: 0.12)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(walletIcon(type), color: Colors.white, size: 26),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          type.label,
                          style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w600),
                        ),
                      ),
                      _statusCircle(onFile),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          onFile ? 'On file · ${docs.first.createdAt.substring(0, 10)}' : 'Not added yet · tap to add',
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ),
                      if (!onFile) _dontHaveChip(app, type),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "I don't have this" — takes the card off the list so nothing nags about it.
  Widget _dontHaveChip(AppState app, DocumentType type) {
    return GestureDetector(
      key: Key('hide-${type.wireValue}'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        app.hideDocument(type);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('${type.label} hidden. You can bring it back below.'),
            action: SnackBarAction(label: 'Undo', onPressed: () => app.unhideDocument(type)),
          ));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.28), borderRadius: BorderRadius.circular(16)),
        child: const Text("I don't have this", style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
      ),
    );
  }

  /// Green check in a circle once the document is on file; an empty outlined
  /// circle while it's still needed.
  Widget _statusCircle(bool onFile) {
    // The check pops in with a little bounce when a document is added.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.elasticOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
      child: Container(
        key: Key(onFile ? 'status-on-file' : 'status-needed'),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: onFile ? walletGreen : Colors.transparent,
          border: onFile ? null : Border.all(color: Colors.white54, width: 2),
          boxShadow: onFile ? [BoxShadow(color: walletGreen.withValues(alpha: 0.5), blurRadius: 12)] : null,
        ),
        child: onFile ? const Icon(Icons.check_rounded, color: Colors.white, size: 21) : null,
      ),
    );
  }

  Widget _documentRow(BuildContext context, DocumentMeta doc, {required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        onTap: onTap,
        radius: 20,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(colors: walletColors(doc.type), begin: Alignment.topLeft, end: Alignment.bottomRight),
              ),
              child: Icon(walletIcon(doc.type), color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (doc.label?.isNotEmpty == true) ? doc.label! : doc.type.label,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  Text(
                    // The title already names the type unless a custom label
                    // replaced it, so only repeat it in that case.
                    [
                      if (doc.label?.isNotEmpty == true) doc.type.label,
                      _formatSize(doc.fileSizeBytes),
                      doc.createdAt.substring(0, 10),
                    ].join(' · '),
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  List<Widget> _consentGateChildren(BuildContext context, AppState app) {
    return [
      FadeSlideIn(
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(gradient: Brand.heroGradient, borderRadius: BorderRadius.circular(20)),
                child: const Icon(Icons.lock_rounded, size: 32, color: Color(0xFF3A1D00)),
              ),
              const SizedBox(height: 16),
              Text('Keep your papers safe', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                'Keep an encrypted copy of important documents, like your ID or Social Security card, so you always have access, even if the physical copy is lost. This is separate from location sharing; you can use one without the other.',
                style: TextStyle(color: Colors.white70, height: 1.45, fontSize: 15),
              ),
              const SizedBox(height: 18),
              const _GatePoint(Icons.enhanced_encryption_rounded, 'Encrypted before it is saved'),
              const _GatePoint(Icons.visibility_off_rounded, 'Only you can open your documents. Staff can never see them.'),
              const _GatePoint(Icons.delete_outline_rounded, 'Delete any document, any time'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      if (app.documentDisclosure != null)
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: AppCard(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text('Full disclosure · v${app.documentDisclosure!.version}', style: const TextStyle(fontWeight: FontWeight.w700)),
              childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              children: [
                Text(app.documentDisclosure!.text, style: const TextStyle(fontSize: 12.5, height: 1.45, color: Colors.white60)),
              ],
            ),
          ),
        )
      else
        const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
      const SizedBox(height: 20),
      GradientButton(
        label: 'Allow document storage',
        icon: Icons.check_rounded,
        loading: app.isLoading,
        onPressed: app.documentDisclosure == null ? null : () => context.read<AppState>().grantDocumentConsent(),
      ),
    ];
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// MARK: - Upload wizard

/// The green used for "on file" checks (iOS system green).
const walletGreen = Color(0xFF34C759);

List<Color> walletColors(DocumentType type) => switch (type) {
      DocumentType.governmentId => const [Color(0xFF3F78B5), Color(0xFF1E3F6E)],
      DocumentType.socialSecurityCard => const [Color(0xFF7D62B0), Color(0xFF473272)],
      DocumentType.birthCertificate => const [Color(0xFFCB8340), Color(0xFF8A4A1B)],
      DocumentType.other => const [Color(0xFF5F6B73), Color(0xFF353D43)],
    };

IconData walletIcon(DocumentType type) => switch (type) {
      DocumentType.governmentId => Icons.badge_outlined,
      DocumentType.socialSecurityCard => Icons.credit_card,
      DocumentType.birthCertificate => Icons.description_outlined,
      DocumentType.other => Icons.insert_drive_file_outlined,
    };

/// Which of the three core documents still aren't on file, in checklist order.
///
/// Documents the person marked "I don't have this" ([hidden]) aren't counted:
/// nothing is asked of them for those.
List<DocumentType> missingCoreDocuments(List<DocumentMeta> documents, {Set<DocumentType> hidden = const {}}) => [
      for (final type in DocumentType.coreChecklist)
        if (!hidden.contains(type) && !documents.any((d) => d.type == type)) type,
    ];

/// One line of plain-language help shown while scanning each document.
String documentTip(DocumentType type) => switch (type) {
      DocumentType.governmentId =>
        "Lay your ID flat in good light. Scan the front, and the back too if it has one.",
      DocumentType.socialSecurityCard => "Scan the front of your Social Security card.",
      DocumentType.birthCertificate =>
        "Scan the whole page so all four corners show. A certified copy works best.",
      DocumentType.other => "Give it a label below so you can find it later.",
    };

class UploadDocumentSheet extends StatefulWidget {
  /// When set, the walkthrough opens straight on scanning this document type.
  final DocumentType? initialType;
  const UploadDocumentSheet({super.key, this.initialType});

  @override
  State<UploadDocumentSheet> createState() => _UploadDocumentSheetState();
}

enum _Step { chooseType, scanAndLabel, success }

class _UploadDocumentSheetState extends State<UploadDocumentSheet> {
  late _Step _step = widget.initialType != null ? _Step.scanAndLabel : _Step.chooseType;
  late DocumentType? _selectedType = widget.initialType;
  DocumentMeta? _savedDocument;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          switch (_step) {
            _Step.chooseType => 'Add a document',
            _Step.scanAndLabel => _selectedType!.label,
            _Step.success => 'Saved',
          },
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        leading: switch (_step) {
          _Step.chooseType => IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
          _Step.scanAndLabel => IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _step = _Step.chooseType),
            ),
          _Step.success => null,
        },
        automaticallyImplyLeading: false,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(animation),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey('$_step-${_selectedType?.name}'), child: _stepBody()),
      ),
    );
  }

  Widget _stepBody() {
    return switch (_step) {
        _Step.chooseType => _ChooseDocumentTypeStep(
            onSelect: (type) => setState(() {
              _selectedType = type;
              _step = _Step.scanAndLabel;
            }),
          ),
        _Step.scanAndLabel => _ScanDocumentStep(
            documentType: _selectedType!,
            onUploaded: (meta) => setState(() {
              _savedDocument = meta;
              _step = _Step.success;
            }),
          ),
        _Step.success => _UploadSuccessStep(
            document: _savedDocument!,
            onNext: (type) => setState(() {
              _selectedType = type;
              _step = _Step.scanAndLabel;
            }),
            onAddAnother: () => setState(() => _step = _Step.chooseType),
            onDone: () => Navigator.of(context).pop(),
          ),
    };
  }
}

class _ChooseDocumentTypeStep extends StatelessWidget {
  final ValueChanged<DocumentType> onSelect;
  const _ChooseDocumentTypeStep({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 16),
          child: Text('What are you adding?', style: TextStyle(fontSize: 17, color: Colors.white70)),
        ),
        for (final (i, type) in DocumentType.values.indexed)
          FadeSlideIn(
            delay: Duration(milliseconds: 50 * i),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PressableScale(
                onTap: () => onSelect(type),
                child: Container(
                  height: 84,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: LinearGradient(colors: walletColors(type), begin: Alignment.topLeft, end: Alignment.bottomRight),
                  ),
                  child: Row(
                    children: [
                      Icon(walletIcon(type), color: Colors.white, size: 30),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(type.label, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                            Builder(builder: (context) {
                              final count = app.documents.where((d) => d.type == type).length;
                              return Text(
                                count > 0 ? '$count on file' : 'Not on file yet',
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              );
                            }),
                          ],
                        ),
                      ),
                      if (app.documents.any((d) => d.type == type))
                        Container(
                          width: 28,
                          height: 28,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: walletGreen),
                          child: const Icon(Icons.check_rounded, size: 18, color: Colors.white),
                        ),
                      const Icon(Icons.chevron_right_rounded, color: Colors.white70),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ScanDocumentStep extends StatefulWidget {
  final DocumentType documentType;
  final ValueChanged<DocumentMeta> onUploaded;
  const _ScanDocumentStep({required this.documentType, required this.onUploaded});

  @override
  State<_ScanDocumentStep> createState() => _ScanDocumentStepState();
}

class _ScanDocumentStepState extends State<_ScanDocumentStep> {
  final _labelController = TextEditingController();
  String? _scanError;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _addFrom(Future<List<ScannedPage>> Function() source) async {
    setState(() => _scanError = null);
    try {
      final pages = await source();
      if (pages.isEmpty || !mounted) return;

      final app = context.read<AppState>();
      final trimmedLabel = _labelController.text.trim();
      DocumentMeta? lastMeta;
      for (var i = 0; i < pages.length; i++) {
        String? pageLabel = trimmedLabel.isEmpty ? null : trimmedLabel;
        if (pages.length > 1) {
          final suffix = 'page ${i + 1}';
          pageLabel = pageLabel != null ? '$pageLabel ($suffix)' : 'Page ${i + 1}';
        }
        final meta = await app.uploadDocument(
          type: widget.documentType,
          label: pageLabel,
          imageBytes: pages[i].bytes,
          mimeType: pages[i].mimeType,
        );
        if (meta == null) {
          if (mounted) setState(() => _scanError = app.errorMessage);
          return;
        }
        lastMeta = meta;
      }
      if (lastMeta != null) widget.onUploaded(lastMeta);
    } catch (e) {
      if (mounted) setState(() => _scanError = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final type = widget.documentType;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        FadeSlideIn(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(colors: walletColors(type), begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(walletIcon(type), color: Colors.white, size: 34),
                const SizedBox(height: 14),
                Text(documentTip(type), style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.4, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        const SectionLabel('Label (optional)'),
        TextField(
          controller: _labelController,
          decoration: const InputDecoration(hintText: 'e.g. "Current license"'),
        ),
        if (_scanError != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Brand.red.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Brand.red),
                const SizedBox(width: 10),
                Expanded(child: Text(_scanError!, style: const TextStyle(color: Brand.red, height: 1.3))),
              ],
            ),
          ),
        ],
        const SizedBox(height: 22),
        GradientButton(
          label: 'Scan with camera',
          icon: Icons.camera_alt_rounded,
          onPressed: app.isUploadingDocument ? null : () => _addFrom(DocumentScannerService.scan),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: app.isUploadingDocument ? null : () => _addFrom(DocumentScannerService.pickFromPhotos),
          icon: const Icon(Icons.photo_library_rounded),
          label: const Text('Choose from photos'),
        ),
        if (app.isUploadingDocument) ...[
          const SizedBox(height: 22),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: const LinearProgressIndicator(minHeight: 6, color: Brand.orange, backgroundColor: Brand.surfaceHigh),
          ),
          const SizedBox(height: 10),
          const Center(child: Text('Uploading, encrypting…', style: TextStyle(color: Colors.white70))),
        ],
      ],
    );
  }
}

class _UploadSuccessStep extends StatelessWidget {
  final DocumentMeta document;
  final ValueChanged<DocumentType> onNext;
  final VoidCallback onAddAnother;
  final VoidCallback onDone;
  const _UploadSuccessStep({
    required this.document,
    required this.onNext,
    required this.onAddAnother,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final missing = missingCoreDocuments(app.documents, hidden: app.hiddenDocuments);
    final checklist = app.documentChecklist;
    final allDone = missing.isEmpty;

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            const SizedBox(height: 12),
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 700),
                curve: Curves.elasticOut,
                builder: (context, v, child) => Transform.scale(scale: v, child: child),
                child: Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: walletGreen,
                    boxShadow: [BoxShadow(color: walletGreen.withValues(alpha: 0.5), blurRadius: 30, spreadRadius: 2)],
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 56),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              '${document.type.label} saved',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              "It's encrypted and ready whenever you need it.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const SizedBox(height: 26),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    allDone ? 'All done' : '${checklist.length - missing.length} of ${checklist.length} on file',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                  const SizedBox(height: 10),
                  for (final type in checklist)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: missing.contains(type) ? Colors.transparent : walletGreen,
                              border: missing.contains(type) ? Border.all(color: Colors.white30, width: 2) : null,
                            ),
                            child: missing.contains(type) ? null : const Icon(Icons.check_rounded, size: 17, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Text(type.label, style: TextStyle(fontSize: 16, color: missing.contains(type) ? Colors.white60 : Colors.white)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            if (missing.isNotEmpty) ...[
              GradientButton(
                label: 'Next: ${missing.first.label}',
                icon: Icons.arrow_forward_rounded,
                onPressed: () => onNext(missing.first),
              ),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: onDone, child: const Text("I'll finish later")),
            ] else ...[
              GradientButton(label: 'Done', icon: Icons.check_rounded, onPressed: onDone),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: onAddAnother, child: const Text('Add another document')),
            ],
          ],
        ),
        if (allDone) const Positioned.fill(child: ConfettiBurst()),
      ],
    );
  }
}

// MARK: - Detail viewer

class DocumentDetailView extends StatefulWidget {
  final DocumentMeta document;
  const DocumentDetailView({super.key, required this.document});

  @override
  State<DocumentDetailView> createState() => _DocumentDetailViewState();
}

class _DocumentDetailViewState extends State<DocumentDetailView> {
  Uint8List? _imageBytes;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await ApiClient.shared.fetchDocument(widget.document.id);
      if (!mounted) return;
      setState(() => _imageBytes = base64Decode(response.fileBase64));
    } catch (e) {
      if (mounted) setState(() => _loadError = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text((widget.document.label?.isNotEmpty == true) ? widget.document.label! : widget.document.type.label),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete this document?'),
                  content: const Text('This permanently deletes the stored copy. This cannot be undone.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Delete', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
              if (confirmed == true && context.mounted) {
                await context.read<AppState>().deleteDocument(widget.document.id);
                if (context.mounted) Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
      body: Center(
        child: _imageBytes != null
            ? InteractiveViewer(child: Image.memory(_imageBytes!))
            : _loadError != null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.orange, size: 40),
                        const SizedBox(height: 8),
                        Text(_loadError!, textAlign: TextAlign.center),
                      ],
                    ),
                  )
                : const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Decrypting…'),
                    ],
                  ),
      ),
    );
  }
}

class _GatePoint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _GatePoint(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Brand.orange),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, height: 1.35))),
        ],
      ),
    );
  }
}
