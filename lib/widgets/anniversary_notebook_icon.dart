import 'package:flutter/material.dart';

@visibleForTesting
class AnniversaryNotebookIconLayout {
  const AnniversaryNotebookIconLayout();

  static const Size canvasSize = Size(64, 72);
  static const Offset contentOffset = Offset(-2, 0);

  static const Rect shadowRect = Rect.fromLTWH(14, 16, 48, 56);
  static const Rect pageBackRect = Rect.fromLTWH(10, 10, 50, 56);
  static const Rect pageFrontRect = Rect.fromLTWH(10, 8, 48, 56);
  static const Rect coverRect = Rect.fromLTWH(12, 4, 44, 58);
  static const Rect strapRect = Rect.fromLTWH(42, 4, 4, 58);
  static const Rect spineRect = Rect.fromLTWH(6, 2, 8, 62);
  static const Rect bookmarkRect = Rect.fromLTWH(28, 56, 6, 14);

  Rect get visualBounds {
    final rects = [
      shadowRect,
      pageBackRect,
      pageFrontRect,
      coverRect,
      strapRect,
      spineRect,
      bookmarkRect,
    ].map((rect) => rect.shift(contentOffset));

    Rect bounds = rects.first;
    for (final rect in rects.skip(1)) {
      bounds = bounds.expandToInclude(rect);
    }
    return bounds;
  }
}

class AnniversaryNotebookIcon extends StatelessWidget {
  const AnniversaryNotebookIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AnniversaryNotebookIconLayout.canvasSize.width,
      height: AnniversaryNotebookIconLayout.canvasSize.height,
      child: Transform.translate(
        offset: AnniversaryNotebookIconLayout.contentOffset,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              bottom: 0,
              right: 2,
              child: Container(
                width: 48,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 10,
                      offset: const Offset(4, 6),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 4,
              top: 10,
              bottom: 6,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: const Color(0xFFCBD5E1), width: 0.5),
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 6,
              top: 8,
              bottom: 8,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: const Color(0xFFE2E8F0), width: 0.5),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 8,
              top: 4,
              bottom: 10,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF60A5FA), Color(0xFF2563EB)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(6),
                    bottomRight: Radius.circular(6),
                    topLeft: Radius.circular(2),
                    bottomLeft: Radius.circular(2),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 8,
              top: 4,
              bottom: 10,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(6),
                    bottomRight: Radius.circular(6),
                    topLeft: Radius.circular(2),
                    bottomLeft: Radius.circular(2),
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 18,
              top: 4,
              bottom: 10,
              width: 4,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A8A).withValues(alpha: 0.6),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 2,
                      offset: const Offset(-1, 0),
                    ),
                  ],
                ),
              ),
            ),
            const Positioned(
              left: 14,
              right: 22,
              top: 10,
              bottom: 10,
              child: Center(
                child: Text(
                  '1',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -1,
                    shadows: [
                      Shadow(
                        color: Color(0x66000000),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 6,
              top: 2,
              bottom: 8,
              width: 8,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 3,
                      offset: const Offset(2, 0),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 28,
              bottom: 2,
              child: Container(
                width: 6,
                height: 14,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(2),
                    bottomRight: Radius.circular(2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 2,
                      offset: Offset(1, 1),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
