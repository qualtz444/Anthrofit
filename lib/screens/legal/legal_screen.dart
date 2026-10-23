import 'package:flutter/material.dart';

import '../../legal/legal_text.dart';

/// Shows [documents] one after another in a full page.
///
/// With [askToAgree], an "I agree" button sits at the bottom and becomes
/// active once the page has been scrolled to the end (straight away if it
/// all fits). Pops with true when agreed. Without it, it is read-only.
class LegalScreen extends StatefulWidget {
  const LegalScreen({
    super.key,
    required this.documents,
    this.askToAgree = false,
  });

  final List<LegalDocument> documents;
  final bool askToAgree;

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  final ScrollController _scroll = ScrollController();
  bool _reachedEnd = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_check);
    // A short page has nothing to scroll.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (_reachedEnd || !_scroll.hasClients) return;
    final p = _scroll.position;
    if (p.pixels >= p.maxScrollExtent - 24) {
      setState(() => _reachedEnd = true);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.documents.length == 1
        ? widget.documents.single.title
        : 'Terms and Privacy';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        key: const ValueKey('legal-scroll'),
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Last updated $kLegalUpdated',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          for (final doc in widget.documents) ...[
            const SizedBox(height: 16),
            Text(doc.title, style: theme.textTheme.headlineSmall),
            for (final s in doc.sections) ...[
              const SizedBox(height: 14),
              Text(s.heading, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(s.body, style: theme.textTheme.bodyMedium),
            ],
          ],
        ],
      ),
      bottomNavigationBar: widget.askToAgree
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_reachedEnd)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Scroll to the end to agree.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    FilledButton(
                      key: const ValueKey('legal-agree'),
                      onPressed: _reachedEnd
                          ? () => Navigator.of(context).pop(true)
                          : null,
                      child: const Text('I agree'),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

/// Opens the Terms and the Privacy Policy together, asking to agree.
/// True when the user agreed.
Future<bool> readAndAgreeToTerms(BuildContext context) async {
  final agreed = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => const LegalScreen(
        documents: [kTermsOfService, kPrivacyPolicy],
        askToAgree: true,
      ),
    ),
  );
  return agreed ?? false;
}

/// Opens one document to read.
void openLegal(BuildContext context, LegalDocument document) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LegalScreen(documents: [document]),
      ),
    );
