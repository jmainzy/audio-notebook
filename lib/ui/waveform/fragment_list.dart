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

class SegmentCard extends StatelessWidget {
  const SegmentCard({
    super.key,
    required this.segment,
    required this.isPlaying,
    required this.isSelected,
    required this.onTap,
    this.onDoubleTap,
    this.onClear,
  });

  final Segment segment;
  final bool isPlaying;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? Colors.amber.withValues(alpha: 0.22)
          : Colors.white.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
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
                      '${formatDuration(Duration(milliseconds: (segment.start * 1000).round()))} - ${formatDuration(Duration(milliseconds: (segment.end * 1000).round()))}',
                      style: const TextStyle(
                        fontFamily: 'Arial',
                        fontSize: 12,
                        color: Color(0xff887b70),
                      ),
                    ),
                    SizedBox(height: Dimens.marginShort),
                    Text(
                      segment.text.isEmpty
                          ? 'Transcription here'
                          : segment.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
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
