import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:wav/wav_file.dart';

class MmsTranscriptionService {
  static const sampleRate = 16000;

  Future<String> get modelDirectory async =>
      path.join((await getApplicationSupportDirectory()).path, 'mms-asr');

  Future<File> prepareAudio(String audioPath) async {
    final directory = await Directory.systemTemp.createTemp('audio_notebook_');
    final output = File(path.join(directory.path, 'audio.wav'));
    try {
      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-i',
        audioPath,
        '-vn',
        '-ac',
        '1',
        '-ar',
        '$sampleRate',
        '-c:a',
        'pcm_s16le',
        output.path,
      ]);
      if (!ReturnCode.isSuccess(await session.getReturnCode())) {
        throw StateError(
          'Could not decode audio: ${await session.getOutput()}',
        );
      }
      return output;
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<List<String>> transcribe(
    File audio,
    List<({double start, double end})> ranges,
  ) async {
    final directory = await modelDirectory;
    final model = File(path.join(directory, 'model.onnx'));
    final vocabulary = File(path.join(directory, 'vocab.json'));
    final tokenizer = File(path.join(directory, 'tokenizer_config.json'));
    if (!await model.exists() ||
        !await vocabulary.exists() ||
        !await tokenizer.exists()) {
      throw StateError(
        'Mvskoke MMS model not installed. Export the model to $directory '
        'as described in the README.',
      );
    }
    final vocabJson = jsonDecode(await vocabulary.readAsString());
    if (vocabJson is! Map || vocabJson['mus'] is! Map) {
      throw const FormatException('The MMS vocabulary has no mus language.');
    }
    final entries = Map<String, dynamic>.from(vocabJson['mus'] as Map);
    final tokens = <int, String>{
      for (final entry in entries.entries) entry.value as int: entry.key,
    };
    final tokenizerJson = jsonDecode(await tokenizer.readAsString());
    if (tokenizerJson is! Map ||
        tokenizerJson['added_tokens_decoder'] is! Map) {
      throw const FormatException('Invalid MMS tokenizer configuration.');
    }
    final addedTokens = tokenizerJson['added_tokens_decoder'] as Map;
    for (final entry in addedTokens.entries) {
      final id = int.parse(entry.key as String);
      final token = entry.value;
      if (token is! Map || token['content'] is! String) {
        throw const FormatException('Invalid MMS added token.');
      }
      tokens[id] = token['content'] as String;
    }
    final blank = entries['[PAD]'];
    if (blank is! int) throw const FormatException('Missing CTC blank token.');

    final wav = Wav.read(await audio.readAsBytes());
    if (wav.samplesPerSecond != sampleRate || wav.channels.length != 1) {
      throw const FormatException('Expected mono 16 kHz audio.');
    }
    final samples = wav.channels.single;
    final session = await OnnxRuntime().createSession(model.path);
    try {
      final results = <String>[];
      for (final range in ranges) {
        final start = (range.start * sampleRate).floor().clamp(
          0,
          samples.length,
        );
        final end = (range.end * sampleRate).ceil().clamp(0, samples.length);
        if (end - start < 400) {
          throw StateError('A segment is too short for MMS transcription.');
        }
        final chunks = <String>[];
        final chunkCount = ((end - start) / (sampleRate * 8)).ceil();
        for (var chunkIndex = 0; chunkIndex < chunkCount; chunkIndex++) {
          final offset = start + ((end - start) * chunkIndex ~/ chunkCount);
          final chunkEnd =
              start + ((end - start) * (chunkIndex + 1) ~/ chunkCount);
          final chunk = samples.sublist(offset, chunkEnd);
          final mean = chunk.reduce((a, b) => a + b) / chunk.length;
          var variance = 0.0;
          for (final sample in chunk) {
            variance += (sample - mean) * (sample - mean);
          }
          final scale = math.sqrt(variance / chunk.length + 1e-7);
          final input = Float32List.fromList(
            chunk.map((sample) => (sample - mean) / scale).toList(),
          );
          final tensor = await OrtValue.fromList(input, [1, input.length]);
          Map<String, OrtValue>? outputs;
          try {
            outputs = await session.run({'input_values': tensor});
            final logits = outputs['logits'];
            if (logits == null ||
                logits.shape.length != 3 ||
                logits.shape[0] != 1 ||
                logits.shape[2] != tokens.length) {
              throw const FormatException('Unexpected MMS output shape.');
            }
            final values = await logits.asFlattenedList();
            chunks.add(decodeCtc(values, logits.shape[2], tokens, blank));
          } finally {
            await tensor.dispose();
            if (outputs != null) {
              for (final output in outputs.values) {
                await output.dispose();
              }
            }
          }
        }
        results.add(chunks.where((chunk) => chunk.isNotEmpty).join(' '));
      }
      return results;
    } finally {
      await session.close();
    }
  }
}

String decodeCtc(
  List<dynamic> logits,
  int classCount,
  Map<int, String> tokens,
  int blank,
) {
  if (classCount <= 0 || logits.length % classCount != 0) {
    throw const FormatException('Invalid CTC logits.');
  }
  final result = StringBuffer();
  int? previous;
  for (var frame = 0; frame < logits.length; frame += classCount) {
    var best = 0;
    for (var index = 1; index < classCount; index++) {
      if ((logits[frame + index] as num) > (logits[frame + best] as num)) {
        best = index;
      }
    }
    if (best != previous && best != blank) {
      final token = tokens[best];
      if (token == null) throw FormatException('Unknown token $best.');
      if (token == '|') {
        result.write(' ');
      } else if (!token.startsWith('[') && !token.startsWith('<')) {
        result.write(token);
      }
    }
    previous = best;
  }
  return result.toString().trim();
}
