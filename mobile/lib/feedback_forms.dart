import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

/// Warehouse feedback inbox for Windows Help / F2 capture forms.
const kWarehouseFeedbackEmail = 'warehouse2@swiftsupply.ca';

Future<void> openFeedbackForm(
  BuildContext context, {
  required String installedVersion,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _MailFormDialog(
      title: 'Send feedback',
      subtitle:
          'Your message is opened in your default mail app addressed to '
          '$kWarehouseFeedbackEmail.',
      subjectPrefix: 'Swift Document Generator feedback',
      installedVersion: installedVersion,
      includeErrorDetails: false,
    ),
  );
}

Future<void> openErrorCaptureForm(
  BuildContext context, {
  required String installedVersion,
  String? prefillDetails,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _MailFormDialog(
      title: 'Error capture (F2)',
      subtitle:
          'Describe what went wrong. Submission opens an e-mail to '
          '$kWarehouseFeedbackEmail.',
      subjectPrefix: 'Swift Document Generator error report',
      installedVersion: installedVersion,
      includeErrorDetails: true,
      initialDetails: prefillDetails,
    ),
  );
}

class _MailFormDialog extends StatefulWidget {
  const _MailFormDialog({
    required this.title,
    required this.subtitle,
    required this.subjectPrefix,
    required this.installedVersion,
    required this.includeErrorDetails,
    this.initialDetails,
  });

  final String title;
  final String subtitle;
  final String subjectPrefix;
  final String installedVersion;
  final bool includeErrorDetails;
  final String? initialDetails;

  @override
  State<_MailFormDialog> createState() => _MailFormDialogState();
}

class _MailFormDialogState extends State<_MailFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _contact;
  late final TextEditingController _summary;
  late final TextEditingController _details;
  var _category = 'General';
  var _sending = false;

  static const _categories = [
    'General',
    'Bug / crash',
    'PDF layout',
    'Logos / Recreate',
    'Presets / sync',
    'Update / installer',
    'Feature request',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _contact = TextEditingController();
    _summary = TextEditingController();
    _details = TextEditingController(text: widget.initialDetails ?? '');
    if (widget.includeErrorDetails) {
      _category = 'Bug / crash';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    _summary.dispose();
    _details.dispose();
    super.dispose();
  }

  String _body() {
    final buf = StringBuffer()
      ..writeln('Swift Document Generator — ${widget.subjectPrefix}')
      ..writeln()
      ..writeln('Version: ${widget.installedVersion}')
      ..writeln('Platform: ${Platform.operatingSystem}')
      ..writeln('Category: $_category')
      ..writeln('Name: ${_name.text.trim().isEmpty ? '(not provided)' : _name.text.trim()}')
      ..writeln(
        'Contact: ${_contact.text.trim().isEmpty ? '(not provided)' : _contact.text.trim()}',
      )
      ..writeln()
      ..writeln('Summary:')
      ..writeln(_summary.text.trim().isEmpty ? '(none)' : _summary.text.trim())
      ..writeln()
      ..writeln(widget.includeErrorDetails ? 'Error / repro steps:' : 'Details:')
      ..writeln(_details.text.trim().isEmpty ? '(none)' : _details.text.trim())
      ..writeln()
      ..writeln('— Sent from in-app ${widget.includeErrorDetails ? 'F2 error capture' : 'Help → Feedback'}');
    return buf.toString();
  }

  Future<void> _submit() async {
    final summary = _summary.text.trim();
    if (summary.isEmpty && _details.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a summary or details before sending.')),
      );
      return;
    }
    setState(() => _sending = true);
    final subject = Uri.encodeComponent(
      '${widget.subjectPrefix}: ${summary.isEmpty ? _category : summary}',
    );
    final body = Uri.encodeComponent(_body());
    final uri = Uri.parse(
      'mailto:$kWarehouseFeedbackEmail?subject=$subject&body=$body',
    );
    try {
      final ok = await launchUrl(uri);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open the mail app. Copy the address: '
              '$kWarehouseFeedbackEmail',
            ),
          ),
        );
        setState(() => _sending = false);
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mail draft opened — send when ready.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open mail: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: Scrollbar(
          thumbVisibility: true,
          interactive: true,
          child: SingleChildScrollView(
            primary: true,
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.subtitle,
                style: const TextStyle(color: SwiftColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _category,
                decoration: const InputDecoration(labelText: 'CATEGORY'),
                items: [
                  for (final c in _categories)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'YOUR NAME (OPTIONAL)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _contact,
                decoration: const InputDecoration(
                  labelText: 'EMAIL / PHONE (OPTIONAL)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _summary,
                decoration: const InputDecoration(labelText: 'SUMMARY'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _details,
                minLines: 5,
                maxLines: 10,
                decoration: InputDecoration(
                  labelText: widget.includeErrorDetails
                      ? 'ERROR DETAILS / STEPS TO REPRODUCE'
                      : 'DETAILS',
                  alignLabelWithHint: true,
                ),
              ),
            ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _sending ? null : _submit,
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_outlined, size: 18),
          label: Text(_sending ? 'Opening…' : 'Submit'),
        ),
      ],
    );
  }
}
