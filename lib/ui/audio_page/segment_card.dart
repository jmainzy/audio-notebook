import 'package:audionotebook/model/voice_segment.dart';
import 'package:audionotebook/utils/dimens.dart';
import 'package:audionotebook/utils/utils.dart';
import 'package:flutter/material.dart';

class SegmentCard extends StatefulWidget {
  const SegmentCard({
    super.key,
    required this.segment,
    required this.isPlaying,
    required this.isSelected,
    required this.onTap,
    required this.onTextChanged,
    required this.onNotesChanged,
    required this.onLanguageChanged,
    required this.onDelete,
    required this.onExport,
    this.onDoubleTap,
    this.onClear,
  });

  final Segment segment;
  final bool isPlaying;
  final bool isSelected;
  final VoidCallback onTap;
  final ValueChanged<String> onTextChanged;
  final ValueChanged<String> onNotesChanged;
  final ValueChanged<SegmentLanguage> onLanguageChanged;
  final VoidCallback onDelete;
  final VoidCallback onExport;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onClear;

  @override
  State<SegmentCard> createState() => _SegmentCardState();
}

class _SegmentCardState extends State<SegmentCard> {
  late final TextEditingController _textController;
  late final TextEditingController _notesController;
  late final FocusNode _textFocusNode;
  late final FocusNode _notesFocusNode;
  bool _isEditingText = false;
  bool _isEditingNotes = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.segment.text);
    _notesController = TextEditingController(text: widget.segment.notes);
    _textFocusNode = FocusNode()..addListener(_handleTextFocusChange);
    _notesFocusNode = FocusNode()..addListener(_handleNotesFocusChange);
  }

  @override
  void didUpdateWidget(covariant SegmentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditingText && oldWidget.segment.text != widget.segment.text) {
      _textController.text = widget.segment.text;
    }
    if (!_isEditingNotes && oldWidget.segment.notes != widget.segment.notes) {
      _notesController.text = widget.segment.notes;
    }
  }

  @override
  void dispose() {
    _textFocusNode
      ..removeListener(_handleTextFocusChange)
      ..dispose();
    if (_isEditingNotes) widget.onNotesChanged(_notesController.text);
    _notesFocusNode
      ..removeListener(_handleNotesFocusChange)
      ..dispose();
    _textController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _startEditingText() {
    setState(() => _isEditingText = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isEditingText) _textFocusNode.requestFocus();
    });
  }

  void _handleTextFocusChange() {
    if (!_textFocusNode.hasFocus) _finishEditingText();
  }

  void _finishEditingText() {
    if (!_isEditingText) return;
    final text = _textController.text;
    setState(() => _isEditingText = false);
    widget.onTextChanged(text);
  }

  void _handleNotesFocusChange() {
    if (!_notesFocusNode.hasFocus) _finishEditingNotes();
  }

  void _finishEditingNotes() {
    if (!_isEditingNotes) return;
    _isEditingNotes = false;
    widget.onNotesChanged(_notesController.text);
  }

  @override
  Widget build(BuildContext context) {
    final languageColor = widget.segment.language.color;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: widget.isSelected ? Colors.amber.shade800 : Colors.transparent,
          width: 2,
        ),
      ),
      child: Material(
        color: languageColor.withValues(alpha: widget.isSelected ? 0.3 : 0.15),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: widget.onTap,
          onDoubleTap: widget.onDoubleTap,
          borderRadius: BorderRadius.circular(8),
          focusColor: Colors.white10,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${formatDuration(Duration(milliseconds: (widget.segment.start * 1000).round()))} - ${formatDuration(Duration(milliseconds: (widget.segment.end * 1000).round()))}',
                              style: const TextStyle(
                                fontFamily: 'Arial',
                                fontSize: 12,
                                color: Color(0xff887b70),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Export clip',
                            onPressed: widget.onExport,
                            icon: const Icon(Icons.download, size: 18),
                          ),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<SegmentLanguage>(
                              value: widget.segment.language,
                              isDense: true,
                              iconSize: 18,
                              items: SegmentLanguage.values
                                  .map(
                                    (language) => DropdownMenuItem(
                                      value: language,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 10,
                                            height: 10,
                                            decoration: BoxDecoration(
                                              color: language.color,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            language.label,
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (language) {
                                if (language != null) {
                                  widget.onLanguageChanged(language);
                                }
                              },
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete segment',
                            onPressed: widget.onDelete,
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints.tightFor(
                              width: 32,
                              height: 32,
                            ),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        ],
                      ),
                      SizedBox(height: Dimens.marginShort),
                      if (_isEditingText)
                        TextField(
                          controller: _textController,
                          focusNode: _textFocusNode,
                          minLines: 1,
                          maxLines: 3,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: 'Transcription here',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onTapOutside: (_) => _textFocusNode.unfocus(),
                          onSubmitted: (_) => _textFocusNode.unfocus(),
                        )
                      else
                        InkWell(
                          onTap: _startEditingText,
                          child: SizedBox(
                            width: double.infinity,
                            child: Text(
                              widget.segment.text.isEmpty
                                  ? 'Transcription here'
                                  : widget.segment.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      SizedBox(height: Dimens.marginShort),
                      TextField(
                        controller: _notesController,
                        focusNode: _notesFocusNode,
                        minLines: 1,
                        maxLines: 2,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Notes',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => _isEditingNotes = true,
                        onTapOutside: (_) => _notesFocusNode.unfocus(),
                        onSubmitted: (_) => _notesFocusNode.unfocus(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
