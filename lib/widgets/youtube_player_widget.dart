import 'dart:async';

import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

class YouTubePlayerWidget extends StatefulWidget {
  final String videoUrl;

  const YouTubePlayerWidget({super.key, required this.videoUrl});

  @override
  State<YouTubePlayerWidget> createState() => _YouTubePlayerWidgetState();
}

class _YouTubePlayerWidgetState extends State<YouTubePlayerWidget> {
  YoutubePlayerController? _controller;

  @override
  void initState() {
    super.initState();
    final videoId = YoutubePlayerController.convertUrlToId(widget.videoUrl);
    if (videoId != null) {
      _controller = YoutubePlayerController.fromVideoId(
        videoId: videoId,
        autoPlay: false,
      );
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) unawaited(controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8.0),
      child: YoutubePlayer(controller: _controller!),
    );
  }
}
