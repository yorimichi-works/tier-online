import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/app_state.dart';
import '../widgets/common_widgets.dart';

class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key, required this.appState});
  final AppState appState;

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

const _categories = [
  'general',
  'rightsInfringement',
  'deletionRequest',
  'other',
];

class _ContactScreenState extends State<ContactScreen> {
  final _formKey = GlobalKey<FormState>();
  final _message = TextEditingController();
  final _email = TextEditingController();
  final _url = TextEditingController();
  String _category = 'general';
  bool _submitting = false;

  @override
  void dispose() {
    _message.dispose();
    _email.dispose();
    _url.dispose();
    super.dispose();
  }

  String _categoryLabel(String category) => switch (category) {
    'rightsInfringement' => context.l10n.t('contactCategoryRights'),
    'deletionRequest' => context.l10n.t('contactCategoryDeletion'),
    'other' => context.l10n.t('contactCategoryOther'),
    _ => context.l10n.t('contactCategoryGeneral'),
  };

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    final ok = await widget.appState.submitContactRequest(
      category: _category,
      message: _message.text.trim(),
      contactEmail: _email.text.trim(),
      relatedUrl: _url.text.trim(),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.t(ok ? 'contactSuccess' : 'contactFailure')),
      ),
    );
    if (ok) {
      _message.clear();
      _url.clear();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.t('contactTitle'))),
    body: SingleChildScrollView(
      child: ContentFrame(
        maxWidth: 640,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.t('contactTitle'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                context.l10n.t('contactCategory'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in _categories)
                    ChoiceChip(
                      label: Text(_categoryLabel(category)),
                      selected: _category == category,
                      onSelected: (_) => setState(() => _category = category),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _message,
                minLines: 5,
                maxLines: 10,
                maxLength: 4000,
                decoration: InputDecoration(
                  labelText: context.l10n.t('contactMessageLabel'),
                  hintText: context.l10n.t('contactMessageHint'),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? context.l10n.t('contactMessageRequired')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: context.l10n.t('contactEmailLabel'),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: context.l10n.t('contactUrlLabel'),
                  hintText: context.l10n.t('contactUrlHint'),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.l10n.t('contactSubmit')),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
