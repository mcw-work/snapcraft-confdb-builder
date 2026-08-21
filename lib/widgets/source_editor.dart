import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

class SourceEditor extends StatefulWidget {
  const SourceEditor({super.key, required this.source, required this.onApply});
  final String source;
  final ValueChanged<String> onApply;
  @override
  State<SourceEditor> createState() => _SourceEditorState();
}

class _SourceEditorState extends State<SourceEditor> {
  late final TextEditingController _controller = TextEditingController(text: widget.source);
  @override
  void didUpdateWidget(covariant SourceEditor oldWidget) { super.didUpdateWidget(oldWidget); if (oldWidget.source != widget.source) _controller.text = widget.source; }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => YaruSection(
    headline: Row(children: [const Expanded(child: Text('Assertion source')), FilledButton(onPressed: () => widget.onApply(_controller.text), child: const Text('Apply source'))]),
    child: TextField(key: const Key('source-editor'), controller: _controller, expands: true, maxLines: null, minLines: null, keyboardType: TextInputType.multiline, style: const TextStyle(fontFamily: 'monospace'), decoration: const InputDecoration(border: OutlineInputBorder())),
  );
}