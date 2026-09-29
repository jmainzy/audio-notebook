import 'package:audionotebook/model/voice_segment.dart';
import 'package:audionotebook/utils/dimens.dart';
import 'package:audionotebook/utils/utils.dart';
import 'package:flutter/material.dart';

class FragmentList extends StatefulWidget {
  final List<Segment> fragments;
  final ValueNotifier<Duration> playbackNotifier;
  final Map<String, String>? rules;
  final int? selectedIndex;

  final Function(int) onSelect;
  final Function(int) onJumpTo;
  final Function(int) onDoubleTap;
  final Function(int) onCapture;
  final Function(int) onClear;
  final void Function(int, String) onTextChanged;

  const FragmentList({
    super.key,
    required this.fragments,
    required this.playbackNotifier,
    this.rules,
    this.selectedIndex,
    required this.onSelect,
    required this.onJumpTo,
    required this.onDoubleTap,
    required this.onCapture,
    required this.onClear,
    required this.onTextChanged,
  });

  @override
  State<FragmentList> createState() => _StudioFragmentListState();
}

class _StudioFragmentListState extends State<FragmentList> {
  final ScrollController _scrollController = ScrollController();
  final double _rowHeight = 120.0;
  int _lastActiveIndex = -1;

  @override
  void initState() {
    super.initState();
    // Listen directly to the playhead for auto-scrolling
    widget.playbackNotifier.addListener(_onPlaybackPositionChanged);
  }

  @override
  void dispose() {
    widget.playbackNotifier.removeListener(_onPlaybackPositionChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onPlaybackPositionChanged() {
    final newIndex = _getActiveIndex(
      widget.fragments,
      widget.playbackNotifier.value,
    );
    if (newIndex != -1 && newIndex != _lastActiveIndex) {
      _lastActiveIndex = newIndex;
      _scrollToIndex(newIndex);
    }
  }

  int _getActiveIndex(List<Segment> frags, Duration pos) {
    final ms = pos.inMilliseconds;
    return frags.indexWhere(
      (f) => ms >= (f.start * 1000) && ms < (f.end * 1000),
    );
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;

    // Put the active item exactly at the top (or 1 row down for slight context)
    final targetIndex = index > 0 ? index - 1 : 0;
    final idealOffset = targetIndex * _rowHeight;
    final min = _scrollController.position.minScrollExtent;
    final max = _scrollController.position.maxScrollExtent;

    _scrollController.animateTo(
      idealOffset.clamp(min, max),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fragments.isEmpty) {
      return Center(
        child: Text("Click \'Detect Segments\' to show audio segments"),
      );
    }

    return ValueListenableBuilder<Duration>(
      valueListenable: widget.playbackNotifier,
      builder: (context, currentPos, _) {
        return ListView.separated(
          controller: _scrollController,
          itemCount: widget.fragments.length,
          itemBuilder: (ctx, i) {
            final f = widget.fragments[i];
            final hasTime = f.start >= 0;

            final isPlaying =
                hasTime &&
                currentPos.inMilliseconds >= (f.start * 1000) &&
                currentPos.inMilliseconds < (f.end * 1000);

            final isSelected = widget.selectedIndex == i;

            final bool isHighlighted = isPlaying || (isSelected && !hasTime);

            return SegmentCard(
              segment: f,
              isPlaying: isPlaying,
              isSelected: isHighlighted,
              onTap: () {
                widget.onSelect(i);
                if (hasTime) widget.onJumpTo(i);
              },
              onDoubleTap: hasTime ? () => widget.onDoubleTap(i) : null,
              onClear: hasTime ? () => widget.onClear(i) : null,
              onTextChanged: (text) => widget.onTextChanged(i, text),
            );
          },
          separatorBuilder: (BuildContext context, int index) {
            return SizedBox(height: Dimens.marginShort);
          },
        );
      },
    );
  }
}

class SegmentCard extends StatefulWidget {
  const SegmentCard({
    super.key,
    required this.segment,
    required this.isPlaying,
    required this.isSelected,
    required this.onTap,
    required this.onTextChanged,
    this.onDoubleTap,
    this.onClear,
  });

  final Segment segment;
  final bool isPlaying;
  final bool isSelected;
  final VoidCallback onTap;
  final ValueChanged<String> onTextChanged;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onClear;

  @override
  State<SegmentCard> createState() => _SegmentCardState();
}

class _SegmentCardState extends State<SegmentCard> {
  late final TextEditingController _textController;
  late final FocusNode _textFocusNode;
  bool _isEditingText = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.segment.text);
    _textFocusNode = FocusNode()..addListener(_handleTextFocusChange);
  }

  @override
  void didUpdateWidget(covariant SegmentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditingText && oldWidget.segment.text != widget.segment.text) {
      _textController.text = widget.segment.text;
    }
  }

  @override
  void dispose() {
    _textFocusNode
      ..removeListener(_handleTextFocusChange)
      ..dispose();
    _textController.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Material(
      color: widget.isSelected
          ? Colors.amber.withValues(alpha: 0.22)
          : Colors.white.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        borderRadius: BorderRadius.circular(10),
        focusColor: Colors.white10,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${formatDuration(Duration(milliseconds: (widget.segment.start * 1000).round()))} - ${formatDuration(Duration(milliseconds: (widget.segment.end * 1000).round()))}',
                      style: const TextStyle(
                        fontFamily: 'Arial',
                        fontSize: 12,
                        color: Color(0xff887b70),
                      ),
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
                      minLines: 1,
                      maxLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Notes',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
