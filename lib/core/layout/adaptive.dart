import 'package:flutter/widgets.dart';

/// Form factor derived from the current window size only — never from the
/// device model. Rotation simply produces a new form factor; no state is
/// tied to it.
enum KpFormFactor { phonePortrait, phoneLandscape, tabletPortrait, tabletLandscape }

extension KpFormFactorX on KpFormFactor {
  bool get isLandscape =>
      this == KpFormFactor.phoneLandscape || this == KpFormFactor.tabletLandscape;
  bool get isTablet =>
      this == KpFormFactor.tabletPortrait || this == KpFormFactor.tabletLandscape;
  bool get isPhone => !isTablet;
}

KpFormFactor formFactorOf(Size size) {
  final landscape = size.width > size.height;
  final tablet = size.shortestSide >= 600;
  if (tablet) {
    return landscape ? KpFormFactor.tabletLandscape : KpFormFactor.tabletPortrait;
  }
  return landscape ? KpFormFactor.phoneLandscape : KpFormFactor.phonePortrait;
}

KpFormFactor formFactorOfContext(BuildContext context) =>
    formFactorOf(MediaQuery.sizeOf(context));

/// Rect that a video of [videoAspect] occupies inside [box] for contain-fit
/// (letterbox) or cover-fit (crop). Overlays (grid, safe areas, masks) must
/// be drawn inside this rect, not over the whole widget.
Rect videoRectIn(Size box, double videoAspect, {bool cover = false}) {
  if (box.isEmpty || videoAspect <= 0) return Offset.zero & box;
  final boxAspect = box.width / box.height;
  double w;
  double h;
  final widthLimited = cover ? boxAspect < videoAspect : boxAspect > videoAspect;
  if (widthLimited) {
    h = box.height;
    w = h * videoAspect;
  } else {
    w = box.width;
    h = w / videoAspect;
  }
  return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
}
