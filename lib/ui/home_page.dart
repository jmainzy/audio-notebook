import 'dart:io';

import 'package:audionotebook/ui/audio_page.dart';
import 'package:audionotebook/model/audio_item.dart';
import 'package:audionotebook/ui/audio_page_manager.dart';
import 'package:audionotebook/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

const supportedAudioExtensions = {
  '.mp3',
  '.m4a',
  '.wav',
  '.aac',
  '.flac',
  '.ogg',
  '.opus',
};

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

Future<Directory> audioDirectory() async {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  return Directory('${home ?? Directory.current.path}/example_audio');
}

Future<List<AudioItem>> loadAudioEntries() async {
  final directory = await audioDirectory();
  if (!await directory.exists()) return [];

  final files =
      directory.listSync().whereType<File>().where((file) {
        final dot = file.path.lastIndexOf('.');
        final extension = dot == -1
            ? ''
            : file.path.substring(dot).toLowerCase();
        return supportedAudioExtensions.contains(extension);
      }).toList()..sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
      );

  final entries = <AudioItem>[];
  for (final file in files) {
    final player = AudioPlayer();
    try {
      final duration = await player.setFilePath(file.path);
      if (duration != null) {
        entries.add(
          AudioItem(
            file: file,
            createdAt: file.statSync().modified,
            duration: duration,
          ),
        );
      }
    } catch (_) {
      // Keep unreadable files out of the list rather than breaking the screen.
    } finally {
      await player.dispose();
    }
  }
  return entries;
}

class _HomePageState extends State<HomePage> {
  late Future<List<AudioItem>> _entries;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() async {
    _entries = loadAudioEntries();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
              sliver: SliverToBoxAdapter(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AUDIO NOTEBOOK',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  letterSpacing: 2.2,
                                  color: const Color(0xff8e8175),
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Your recordings',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xff292521),
                                ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _refresh,
                      tooltip: 'Refresh recordings',
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              sliver: SliverToBoxAdapter(
                child: FutureBuilder<List<AudioItem>>(
                  future: _entries,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 48),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return const _EmptyState(
                        message: 'Could not read example_audio.',
                      );
                    }
                    final entries = snapshot.data ?? [];
                    if (entries.isEmpty) {
                      return const _EmptyState(
                        message: 'Add audio files to ~/example_audio.',
                      );
                    }
                    return Column(
                      children: [
                        for (final entry in entries)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _AudioListItem(entry: entry),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 48),
    child: Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(fontFamily: 'Arial', color: Color(0xff887b70)),
      ),
    ),
  );
}

class _AudioListItem extends StatelessWidget {
  const _AudioListItem({required this.entry});
  final AudioItem entry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                AudioDetailPage(entry: entry, pageManager: AudioPageManager()),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xffd97757).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.graphic_eq, color: Color(0xffd97757)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xff292521),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      entry.filename,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Arial',
                        fontSize: 12,
                        color: Color(0xff887b70),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${formatDate(context, entry.createdAt)}  ·  ${formatTime(context, entry.createdAt)}',
                      style: const TextStyle(
                        fontFamily: 'Arial',
                        fontSize: 12,
                        color: Color(0xff887b70),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatDuration(entry.duration),
                style: const TextStyle(
                  fontFamily: 'Arial',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xff887b70),
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xffb4a79b)),
            ],
          ),
        ),
      ),
    );
  }
}
