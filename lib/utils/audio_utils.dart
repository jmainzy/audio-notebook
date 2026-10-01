import 'dart:io';

import 'package:flutter/services.dart';
import 'package:just_waveform/just_waveform.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

Logger logger = Logger();

class AudioUtils {
  static Future<Stream<WaveformProgress>?> generateWaveform(
    String audioPath,
  ) async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (!await tempDir.exists()) await tempDir.create(recursive: true);

      final stat = await File(audioPath).stat();
      final fileHash = '${stat.size}_${stat.modified.millisecondsSinceEpoch}';

      File audioFile;
      if (audioPath.contains('assets')) {
        // get the file from assets
        final audioData = (await rootBundle.load(audioPath)).buffer
            .asUint8List();
        audioFile = File(
          path.join(tempDir.path, '${path.basename(audioPath)}_$fileHash'),
        );
        await audioFile.writeAsBytes(audioData);
      } else {
        audioFile = File(audioPath);
      }
      final waveFile = File(
        path.join(tempDir.path, '${path.basename(audioPath)}_$fileHash.wave'),
      );

      return JustWaveform.extract(
        audioInFile: audioFile,
        waveOutFile: waveFile,
      );
    } catch (e) {
      logger.e("Waveform error: $e");
    }
    return null;
  }
}
