import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

class VideoLayer extends StatelessWidget {
  const VideoLayer({
    super.key,
    required this.height,
    required this.tracks,
    required this.localVideoTrack,
    required this.previewDx,
    required this.previewDy,
    required this.onPreviewPositionChanged,
    required this.statusOverlay,
    this.showLocalPreview = true,
  });

  final double height;
  final List<VideoTrack> tracks;
  final VideoTrack? localVideoTrack;
  final double previewDx;
  final double previewDy;
  final ValueChanged<Offset> onPreviewPositionChanged;
  final Widget statusOverlay;
  final bool showLocalPreview;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final previewMaxX = constraints.maxWidth - 96;
          final previewMaxY = constraints.maxHeight - 72;
          final maxX = previewMaxX > 0 ? previewMaxX : 0.0;
          final maxY = previewMaxY > 0 ? previewMaxY : 0.0;
          final clampedDx = previewDx.clamp(0.0, maxX).toDouble();
          final clampedDy = previewDy.clamp(0.0, maxY).toDouble();

          if (showLocalPreview && localVideoTrack != null) {
            if (previewDx == 0 && previewDy == 0 && maxX > 0 && maxY > 0) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                onPreviewPositionChanged(Offset(maxX - 12, 12));
              });
            } else if (clampedDx != previewDx || clampedDy != previewDy) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                onPreviewPositionChanged(Offset(clampedDx, clampedDy));
              });
            }
          }

          return Stack(
            children: [
              Positioned.fill(
                child: tracks.isEmpty
                    ? const Center(child: Text('Waiting for avatar video...'))
                    : VideoTrackRenderer(tracks.first),
              ),
              statusOverlay,
              if (showLocalPreview && localVideoTrack != null)
                Positioned(
                  left: clampedDx,
                  top: clampedDy,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      final nextDx = (clampedDx + details.delta.dx).clamp(0.0, maxX).toDouble();
                      final nextDy = (clampedDy + details.delta.dy).clamp(0.0, maxY).toDouble();
                      onPreviewPositionChanged(Offset(nextDx, nextDy));
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 96,
                        height: 72,
                        child: IgnorePointer(ignoring: true, child: VideoTrackRenderer(localVideoTrack!)),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
