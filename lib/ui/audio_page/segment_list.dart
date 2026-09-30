import 'package:audionotebook/model/voice_segment.dart';
import 'package:audionotebook/ui/audio_page/segment_card.dart';
import 'package:audionotebook/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

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
  final Function(int) onDelete;
  final void Function(int, String) onTextChanged;
  final void Function(int, String) onNotesChanged;
  final void Function(int, SegmentLanguage) onLanguageChanged;

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
    required this.onDelete,
    required this.onTextChanged,
    required this.onNotesChanged,
    required this.onLanguageChanged,
  });

  @override
  State<FragmentList> createState() => _StudioFragmentListState();
}

class _StudioFragmentListState extends State<FragmentList> {
  final ItemScrollController _itemScrollController = ItemScrollController();
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
    if (!_itemScrollController.isAttached) return;

    _itemScrollController.scrollTo(
      index: index,
      alignment: 0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fragments.isEmpty) {
      return Center(
        child: Text("Click 'Detect Segments' to show audio segments"),
      );
    }

    return ValueListenableBuilder<Duration>(
      valueListenable: widget.playbackNotifier,
      builder: (context, currentPos, _) {
        return ScrollablePositionedList.separated(
          itemScrollController: _itemScrollController,
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
              onDelete: () => widget.onDelete(i),
              onTextChanged: (text) => widget.onTextChanged(i, text),
              onNotesChanged: (notes) => widget.onNotesChanged(i, notes),
              onLanguageChanged: (language) =>
                  widget.onLanguageChanged(i, language),
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


