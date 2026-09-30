import 'package:audionotebook/model/voice_segment.dart';
import 'package:flutter/material.dart';

extension SegmentLanguageStyle on SegmentLanguage {
  String get label => switch (this) {
    SegmentLanguage.mvskoke => 'Mvskoke',
    SegmentLanguage.english => 'English',
    SegmentLanguage.mixed => 'Mixed',
  };

  Color get color => switch (this) {
    SegmentLanguage.mvskoke => const Color(0xff008577),
    SegmentLanguage.english => const Color(0xff3977c3),
    SegmentLanguage.mixed => const Color(0xffd17a00),
  };
}
