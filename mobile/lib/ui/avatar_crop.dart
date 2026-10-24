import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../social_strings.dart';
import '../strings.dart';
import '../together/profiles.dart';
import 'together_widgets.dart';

/// The side of the square the phone sends: twice what the server keeps (256 px), so its own
/// resize does the last step.
const avatarSide = 512;

/// Why a picture cannot become an avatar before anything is sent.
enum AvatarIssue { tooBig, wrongType, unreadable }

/// PNG or JPEG by their first bytes, as the server checks them.
bool isPngOrJpeg(Uint8List bytes) =>
    bytes.length > 3 &&
    ((bytes[0] == 0x89 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x4E &&
            bytes[3] == 0x47) ||
        (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF));

/// The picture as picked, checked against the server's limits.
AvatarIssue? avatarIssue(Uint8List bytes) {
  if (bytes.length > ProfileLimits.avatarMaxBytes) return AvatarIssue.tooBig;
  if (!isPngOrJpeg(bytes)) return AvatarIssue.wrongType;
  return null;
}

/// Where the square shown sits in the picture, in the picture's pixels: [offset] is the
/// picture's top left in the frame, [scale] screen points per picture pixel.
Rect cropOf({
  required Size image,
  required double frame,
  required Offset offset,
  required double scale,
}) {
  final side = min(frame / scale, min(image.width, image.height));
  final left = (-offset.dx / scale).clamp(0.0, image.width - side);
  final top = (-offset.dy / scale).clamp(0.0, image.height - side);
  return Rect.fromLTWH(left, top, side, side);
}

/// The square [crop] of [image] drawn at most [avatarSide] pixels a side, as a PNG.
Future<Uint8List> squarePng(ui.Image image, Rect crop) async {
  final side = min(avatarSide, crop.width.round()).clamp(1, avatarSide);
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    image,
    crop,
    Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
    Paint()..filterQuality = FilterQuality.high,
  );
  final square = await recorder.endRecording().toImage(side, side);
  final data = await square.toByteData(format: ui.ImageByteFormat.png);
  square.dispose();
  return data!.buffer.asUint8List();
}

/// Crops a picked picture to a square: drag it, pinch or slide to zoom, the round mask shows
/// what friends will see. Pops the square PNG, or null.
class AvatarCropScreen extends StatefulWidget {
  const AvatarCropScreen({super.key, required this.image});

  /// Decoded, upright (the platform's decoder turns it as the camera held it).
  final ui.Image image;

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  static const maxZoom = 5.0;
  double _frame = 0;
  double _zoom = 1;
  Offset _offset = Offset.zero;
  double _startZoom = 1;
  Offset _startFocal = Offset.zero;
  Offset _startOffset = Offset.zero;
  bool _saving = false;

  Size get _size =>
      Size(widget.image.width.toDouble(), widget.image.height.toDouble());

  double get _base => _frame / min(_size.width, _size.height);
  double get _scale => _base * _zoom;

  /// Keeps the picture over the whole frame.
  Offset _clamp(Offset offset) => Offset(
    offset.dx.clamp(_frame - _size.width * _scale, 0.0),
    offset.dy.clamp(_frame - _size.height * _scale, 0.0),
  );

  /// Zooms around a point of the frame, the middle unless told.
  void _zoomTo(double zoom, [Offset? around]) {
    final focal = around ?? Offset(_frame / 2, _frame / 2);
    final point = (focal - _offset) / _scale;
    _zoom = zoom.clamp(1.0, maxZoom);
    _offset = _clamp(focal - point * _scale);
  }

  void _layout(double frame) {
    if (frame == _frame) return;
    _frame = frame;
    // Centred at first.
    _offset = _clamp(
      Offset(
        (frame - _size.width * _scale) / 2,
        (frame - _size.height * _scale) / 2,
      ),
    );
  }

  Future<void> _use() async {
    setState(() => _saving = true);
    final crop = cropOf(
      image: _size,
      frame: _frame,
      offset: _offset,
      scale: _scale,
    );
    final png = await squarePng(widget.image, crop);
    if (mounted) Navigator.of(context).pop(png);
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return Scaffold(
      backgroundColor: togetherInk,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final frame = min(
              constraints.maxHeight - 28,
              constraints.maxWidth * 0.55,
            ).floorToDouble();
            _layout(frame);
            return Row(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 24, 14),
                  child: GestureDetector(
                    onScaleStart: (details) {
                      _startZoom = _zoom;
                      _startFocal = details.localFocalPoint;
                      _startOffset = _offset;
                    },
                    onScaleUpdate: (details) => setState(() {
                      _offset = _clamp(
                        _startOffset + details.localFocalPoint - _startFocal,
                      );
                      if (details.scale != 1) {
                        _zoomTo(
                          _startZoom * details.scale,
                          details.localFocalPoint,
                        );
                      }
                    }),
                    child: SizedBox.square(
                      dimension: frame,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Stack(
                          children: [
                            Positioned(
                              left: _offset.dx,
                              top: _offset.dy,
                              width: _size.width * _scale,
                              height: _size.height * _scale,
                              child: RawImage(
                                image: widget.image,
                                fit: BoxFit.fill,
                                filterQuality: FilterQuality.medium,
                              ),
                            ),
                            const Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(painter: _RoundMask()),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 18, 24, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          texts.changeAvatar,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          texts.cropHint,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Icon(
                              Icons.zoom_out_rounded,
                              color: Colors.white38,
                              size: 18,
                            ),
                            Expanded(
                              child: Slider(
                                value: _zoom,
                                min: 1,
                                max: maxZoom,
                                label: texts.zoom,
                                onChanged: (value) =>
                                    setState(() => _zoomTo(value)),
                              ),
                            ),
                            const Icon(
                              Icons.zoom_in_rounded,
                              color: Colors.white38,
                              size: 18,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            TextButton(
                              onPressed: _saving
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              child: Text(
                                texts.cancel,
                                style: const TextStyle(color: Colors.white60),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _saving ? null : _use,
                              child: Text(texts.useAvatar),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Darkens the corners outside the circle an avatar is drawn in.
class _RoundMask extends CustomPainter {
  const _RoundMask();

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(Offset.zero & size);
    canvas.drawPath(outside, Paint()..color = const Color(0x99000000));
    canvas.drawCircle(
      size.center(Offset.zero),
      size.shortestSide / 2 - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0x66FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_RoundMask old) => false;
}
