import 'package:flutter/material.dart';

class PublishConfirmationDialog extends StatefulWidget {
  const PublishConfirmationDialog({super.key, required this.schemaName, required this.onConfirm});

  final String schemaName;
  final VoidCallback onConfirm;

  @override
  State<PublishConfirmationDialog> createState() => _PublishConfirmationDialogState();
}

class _PublishConfirmationDialogState extends State<PublishConfirmationDialog> {
  var _enteredName = '';

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Publish ConfDB schema'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Type ${widget.schemaName} exactly to publish this schema.'),
        const SizedBox(height: 12),
        TextField(
          key: const Key('schema-name-confirmation'),
          autofocus: true,
          onChanged: (value) => setState(() => _enteredName = value),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        key: const Key('confirm-publish-button'),
        onPressed: _enteredName == widget.schemaName ? widget.onConfirm : null,
        child: const Text('Publish'),
      ),
    ],
  );
}