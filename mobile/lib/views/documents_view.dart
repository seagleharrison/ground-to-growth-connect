import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/biometric_auth.dart';
import '../services/document_scanner_service.dart';

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

    return Scaffold(
      appBar: AppBar(title: const Text('My documents')),
      body: RefreshIndicator(
        onRefresh: () => context.read<AppState>().refreshDocumentConsent(),
        child: granted ? _buildDocumentsList(context, app) : _buildConsentGate(context, app),
      ),
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

  Widget _buildDocumentsList(BuildContext context, AppState app) {
    final missing = missingCoreDocuments(app.documents);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _checklistCard(context, app),
        const SizedBox(height: 16),
        if (missing.isNotEmpty) ...[
          FilledButton.icon(
            onPressed: () => _openWizard(startAt: missing.first),
            icon: const Icon(Icons.document_scanner_outlined),
            label: Text(missing.length == DocumentType.coreChecklist.length
                ? 'Start: ${missing.first.label}'
                : 'Next: ${missing.first.label}'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _openWizard(),
            child: const Text('Add a different document'),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: walletGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.verified, color: walletGreen),
                SizedBox(width: 10),
                Expanded(child: Text("All three documents are on file. You're all set.")),
              ],
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _openWizard(),
            child: const Text('Add another document'),
          ),
        ],
        if (app.documents.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text('All documents', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          for (final doc in app.documents)
            _documentRow(context, doc, onTap: () => _authenticateThenRun(
              "Verify it's you before viewing this document",
              () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => DocumentDetailView(document: doc)),
              ),
            )),
        ],
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => context.read<AppState>().revokeDocumentConsent(),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Stop storing documents'),
        ),
        const SizedBox(height: 8),
        Text(
          'This does not delete documents already stored — delete those individually. '
          'It only stops you from uploading new ones until you opt back in.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  /// The three core documents as a stack of wallet cards, like Apple Wallet:
  /// each card peeks out from behind the next. A green check in a circle on
  /// the right means it's on file; an empty circle means it's still needed.
  /// Tapping a card adds that document, or opens it if it's already on file.
  Widget _checklistCard(BuildContext context, AppState app) {
    final total = DocumentType.coreChecklist.length;
    final done = total - missingCoreDocuments(app.documents).length;

    const cardHeight = 176.0;
    const peek = 84.0; // how much of each card shows above the next one
    final stackHeight = peek * (total - 1) + cardHeight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Your documents', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            Text(
              '$done of $total on file',
              style: TextStyle(color: done == total ? walletGreen : Colors.grey, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: stackHeight,
          child: Stack(
            children: [
              for (final (index, type) in DocumentType.coreChecklist.indexed)
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
      ],
    );
  }

  Widget _walletCard(BuildContext context, AppState app, DocumentType type) {
    final docs = app.documents.where((d) => d.type == type).toList();
    final onFile = docs.isNotEmpty;
    final colors = walletColors(type);

    return GestureDetector(
      key: Key('wallet-card-${type.wireValue}'),
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
                  const Spacer(),
                  Text(
                    onFile ? 'On file · ${docs.first.createdAt.substring(0, 10)}' : 'Not added yet · tap to add',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Green check in a circle once the document is on file; an empty outlined
  /// circle while it's still needed.
  Widget _statusCircle(bool onFile) {
    return Container(
      key: Key(onFile ? 'status-on-file' : 'status-needed'),
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: onFile ? walletGreen : Colors.transparent,
        border: onFile ? null : Border.all(color: Colors.white54, width: 2),
      ),
      child: onFile ? const Icon(Icons.check, color: Colors.white, size: 21) : null,
    );
  }

  Widget _documentRow(BuildContext context, DocumentMeta doc, {required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(_iconFor(doc.type), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (doc.label?.isNotEmpty == true) ? doc.label! : doc.type.label,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        // The title already names the type unless a custom
                        // label replaced it, so only repeat it in that case.
                        [
                          if (doc.label?.isNotEmpty == true) doc.type.label,
                          _formatSize(doc.fileSizeBytes),
                          doc.createdAt.substring(0, 10),
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConsentGate(BuildContext context, AppState app) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(Icons.lock_outline, size: 40, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 8),
              const Text('Store a document', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 8),
              const Text(
                'Keep an encrypted copy of important documents — like your ID or Social Security '
                'card — so you always have access, even if the physical copy is lost. This is '
                'separate from location sharing; you can use one without the other.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (app.documentDisclosure != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Disclosure · v${app.documentDisclosure!.version}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(app.documentDisclosure!.text, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          )
        else
          const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: app.isLoading ? null : () => context.read<AppState>().grantDocumentConsent(),
          child: const Text('Allow document storage'),
        ),
      ],
    );
  }

  IconData _iconFor(DocumentType type) => switch (type) {
        DocumentType.governmentId => Icons.badge_outlined,
        DocumentType.socialSecurityCard => Icons.credit_card,
        DocumentType.birthCertificate => Icons.description_outlined,
        DocumentType.other => Icons.insert_drive_file_outlined,
      };

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
List<DocumentType> missingCoreDocuments(List<DocumentMeta> documents) => [
      for (final type in DocumentType.coreChecklist)
        if (!documents.any((d) => d.type == type)) type,
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
        title: Text(switch (_step) {
          _Step.chooseType => 'Add a document',
          _Step.scanAndLabel => _selectedType!.label,
          _Step.success => 'Saved',
        }),
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
      body: switch (_step) {
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
      },
    );
  }
}

class _ChooseDocumentTypeStep extends StatelessWidget {
  final ValueChanged<DocumentType> onSelect;
  const _ChooseDocumentTypeStep({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('What are you adding?', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        for (final type in DocumentType.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onSelect(type),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(type.label, style: const TextStyle(fontWeight: FontWeight.w500)),
                            Builder(builder: (context) {
                              final count = app.documents.where((d) => d.type == type).length;
                              return Text(
                                count > 0 ? '$count on file' : 'Not on file yet',
                                style: Theme.of(context).textTheme.bodySmall,
                              );
                            }),
                          ],
                        ),
                      ),
                      if (app.documents.any((d) => d.type == type))
                        const Icon(Icons.check_circle, color: walletGreen, size: 20),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right, size: 18),
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Icon(_iconForType(widget.documentType), color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Text(widget.documentType.label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 12),
        Text(documentTip(widget.documentType), style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 20),
        const Text('Label (optional)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: _labelController,
          decoration: const InputDecoration(
            hintText: 'e.g. "Current license"',
            border: OutlineInputBorder(),
          ),
        ),
        if (_scanError != null) ...[
          const SizedBox(height: 12),
          Text(_scanError!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: app.isUploadingDocument ? null : () => _addFrom(DocumentScannerService.scan),
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('Scan with camera'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: app.isUploadingDocument ? null : () => _addFrom(DocumentScannerService.pickFromPhotos),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Choose from photos'),
        ),
        if (app.isUploadingDocument) ...[
          const SizedBox(height: 16),
          const Row(
            children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Text('Uploading, encrypting…'),
            ],
          ),
        ],
      ],
    );
  }

  IconData _iconForType(DocumentType type) => switch (type) {
        DocumentType.governmentId => Icons.badge_outlined,
        DocumentType.socialSecurityCard => Icons.credit_card,
        DocumentType.birthCertificate => Icons.description_outlined,
        DocumentType.other => Icons.insert_drive_file_outlined,
      };
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
    final missing = missingCoreDocuments(app.documents);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 16),
        const Icon(Icons.check_circle, color: walletGreen, size: 64),
        const SizedBox(height: 16),
        Text(
          '${document.type.label} saved',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 8),
        const Text("It's encrypted and ready whenever you need it.", textAlign: TextAlign.center),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                missing.isEmpty ? 'All done' : '${DocumentType.coreChecklist.length - missing.length} of ${DocumentType.coreChecklist.length} on file',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              for (final type in DocumentType.coreChecklist)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        missing.contains(type) ? Icons.circle_outlined : Icons.check_circle,
                        color: missing.contains(type) ? Colors.grey : walletGreen,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(type.label),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (missing.isNotEmpty) ...[
          FilledButton(
            onPressed: () => onNext(missing.first),
            child: Text('Next: ${missing.first.label}'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onDone, child: const Text("I'll finish later")),
        ] else ...[
          FilledButton(onPressed: onDone, child: const Text('Done')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onAddAnother, child: const Text('Add another document')),
        ],
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
