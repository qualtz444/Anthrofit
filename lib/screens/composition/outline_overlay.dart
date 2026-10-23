import 'package:flutter/material.dart';

import '../../composition/silhouette_features.dart';

/// One body outline to draw, in a colour.
class OutlineLayer {
  const OutlineLayer({required this.mask, required this.color});

  final SilhouetteMask mask;
  final Color color;
}

/// Draws one or more body outlines over each other, scaled so each body's
/// head-to-foot height fills the same space and centred on the body's own
/// middle. Standing a little nearer or further from the phone then does not
/// look like a change in size; only shape differences remain.
class OutlineOverlay extends StatelessWidget {
  const OutlineOverlay({super.key, required this.layers, this.height = 260});

  final List<OutlineLayer> layers;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(painter: _OutlinePainter(layers)),
  );
}

class _Extent {
  const _Extent(this.top, this.bottom, this.centre);
  final int top;
  final int bottom;
  final double centre;
}

_Extent? _extentOf(SilhouetteMask m) {
  var top = -1;
  var bottom = -1;
  final columns = <int>[];
  for (var y = 0; y < m.height; y++) {
    final row = y * m.width;
    var any = false;
    for (var x = 0; x < m.width; x++) {
      if (m.mask[row + x] != 0) {
        any = true;
        columns.add(x);
      }
    }
    if (any) {
      if (top < 0) top = y;
      bottom = y;
    }
  }
  if (top < 0 || bottom <= top) return null;
  columns.sort();
  return _Extent(top, bottom, columns[columns.length ~/ 2].toDouble());
}

class _OutlinePainter extends CustomPainter {
  _OutlinePainter(this.layers);

  final List<OutlineLayer> layers;

  @override
  void paint(Canvas canvas, Size size) {
    for (final layer in layers) {
      final m = layer.mask;
      final e = _extentOf(m);
      if (e == null) continue;
      // Pixels per mask row, so the body spans the full height.
      final scale = size.height / (e.bottom - e.top + 1);
      final paint = Paint()..color = layer.color;
      for (var y = e.top; y <= e.bottom; y++) {
        final row = y * m.width;
        var x = 0;
        while (x < m.width) {
          if (m.mask[row + x] == 0) {
            x++;
            continue;
          }
          final start = x;
          while (x < m.width && m.mask[row + x] != 0) {
            x++;
          }
          canvas.drawRect(
            Rect.fromLTWH(
              size.width / 2 + (start - e.centre) * scale,
              (y - e.top) * scale,
              (x - start) * scale,
              scale + 0.5, // overlap a hair so rows do not show gaps
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_OutlinePainter old) => old.layers != layers;
}
