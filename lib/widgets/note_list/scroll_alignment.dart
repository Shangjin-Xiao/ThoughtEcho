bool shouldSkipVisibleTargetAlignment({
  required double targetOffset,
  required double currentOffset,
  required double viewportExtent,
  required bool forceAlignToTop,
}) {
  if (forceAlignToTop || viewportExtent <= 0) {
    return false;
  }

  return targetOffset >= currentOffset &&
      targetOffset < currentOffset + viewportExtent;
}
