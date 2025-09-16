import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';

/// A production-ready image analysis utility that scores regions based on
/// edge detection, darkness, and saturation characteristics.
///
/// Optimized to use the built-in Sobel edge detection from the image package
/// for better performance and accuracy.
class ImageRegionAnalyzer {
  // Configuration constants
  static const double _defaultPercentileThreshold = 0.35;
  static const double _defaultEdgeWeight = 0.7;
  static const double _defaultDarknessWeight = 0.3;
  static const double _defaultSaturationPower = 1.5;
  static const double _inv255 = 1.0 / 255.0;
  static const double _epsilon = 1e-5;

  /// Scores a region directly from the source image without creating a crop.
  ///
  /// Uses the built-in Sobel edge detection combined with darkness and saturation
  /// weighting to identify regions with subtle edge features (like fine hair).
  ///
  /// Parameters:
  /// - [src]: Source image to analyze
  /// - [x], [y]: Top-left corner of the region to analyze
  /// - [w], [h]: Width and height of the region
  /// - [percentileThreshold]: Percentile for adaptive darkness threshold (0.0-1.0)
  /// - [edgeWeight]: Weight for edge component in final score (0.0-1.0)
  /// - [darknessWeight]: Weight for darkness component in final score (0.0-1.0)
  /// - [saturationPower]: Power applied to saturation boost (higher = more selective)
  /// - [useBuiltinSobel]: Whether to use the optimized built-in Sobel operator
  ///
  /// Returns: Score from 0.0 to 1.0, where higher values indicate more relevant features
  ///
  /// Throws:
  /// - [ArgumentError]: If parameters are invalid
  /// - [StateError]: If image processing fails
  static double scoreRegion({
    required img.Image src,
    required int x,
    required int y,
    required int w,
    required int h,
    double percentileThreshold = _defaultPercentileThreshold,
    double edgeWeight = _defaultEdgeWeight,
    double darknessWeight = _defaultDarknessWeight,
    double saturationPower = _defaultSaturationPower,
    bool useBuiltinSobel = true,
  }) {
    // Validate inputs
    _validateInputs(
      src,
      x,
      y,
      w,
      h,
      percentileThreshold,
      edgeWeight,
      darknessWeight,
    );

    // Ensure weights sum to 1.0
    final totalWeight = edgeWeight + darknessWeight;
    if ((totalWeight - 1.0).abs() > _epsilon) {
      edgeWeight = edgeWeight / totalWeight;
      darknessWeight = darknessWeight / totalWeight;
    }

    try {
      if (useBuiltinSobel) {
        return _scoreRegionWithOpenCV(
          region: src,
          x: x,
          y: y,
          w: w,
          h: h,
          percentileThreshold: percentileThreshold,
          edgeWeight: edgeWeight,
          darknessWeight: darknessWeight,
          saturationPower: saturationPower,
        );
      } else {
        return _scoreRegionWithCustomSobel(
          src: src,
          x: x,
          y: y,
          w: w,
          h: h,
          percentileThreshold: percentileThreshold,
          edgeWeight: edgeWeight,
          darknessWeight: darknessWeight,
          saturationPower: saturationPower,
        );
      }
    } catch (e) {
      throw StateError('Failed to process image region: $e');
    }
  }

  static double _scoreRegionWithBuiltinSobel({
    required img.Image src,
    required int x,
    required int y,
    required int w,
    required int h,
    required double
    percentileThreshold, // now used to pick top fraction of darkSkin
    required double edgeWeight,
    required double darknessWeight,
    required double saturationPower,
  }) {
    const double _eps = 1e-6;
    const List<double> _scales = [1.0, 0.7]; // two levels are enough for speed
    const double _edgeThrPct = 0.80; // robust per-scale threshold
    const int _blurRadius = 2; // smoother skin baseline helps subtle hair

    // Clamp region
    final bounds = _clampRegion(src, x, y, w, h);
    final ww = bounds.width, hh = bounds.height;
    if (ww < 3 || hh < 3) return 0.0;

    // Extract and blur for skin baseline
    final region = img.copyCrop(
      src,
      x: bounds.x0,
      y: bounds.y0,
      width: ww,
      height: hh,
    );
    final blurred = img.gaussianBlur(region.clone(), radius: _blurRadius);

    final total = ww * hh;
    final lumN = Float32List(total); // 0..1
    final skinN = Float32List(total); // 0..1
    final sats = Float32List(total); // 0..1

    for (int yy = 0; yy < hh; yy++) {
      for (int xx = 0; xx < ww; xx++) {
        final i = yy * ww + xx;
        final p = region.getPixel(xx, yy);
        final pb = blurred.getPixel(xx, yy);

        // luminance
        lumN[i] = p.luminanceNormalized.toDouble();
        skinN[i] = pb.luminanceNormalized.toDouble();

        // saturation (HSV-like)
        final r = p.r * _inv255, g = p.g * _inv255, b = p.b * _inv255;
        final maxC = math.max(r, math.max(g, b));
        final minC = math.min(r, math.min(g, b));
        sats[i] = (maxC - minC) / (maxC + minC + _eps);
      }
    }

    // Multi-scale Sobel (built-in), aligned to base size
    final List<Float32List> edgesByScale = [];
    for (final s in _scales) {
      img.Image work = region;
      if (s != 1.0) {
        final nw = math.max(1, (ww * s).round());
        final nh = math.max(1, (hh * s).round());
        work = img.copyResize(
          region,
          width: nw,
          height: nh,
          interpolation: img.Interpolation.cubic,
        );
      }
      final sob = img.sobel(work, amount: 1.0);
      final sobAligned =
          (sob.width == ww && sob.height == hh)
              ? sob
              : img.copyResize(
                sob,
                width: ww,
                height: hh,
                interpolation: img.Interpolation.linear,
              );

      final e = Float32List(total);
      for (int yy = 0; yy < hh; yy++) {
        for (int xx = 0; xx < ww; xx++) {
          final i = yy * ww + xx;
          final ep = sobAligned.getPixel(xx, yy);
          e[i] = ep.luminanceNormalized.toDouble(); // 0..1
        }
      }
      edgesByScale.add(e);
    }

    double _percentileF32(Float32List arr, double p) {
      final tmp = arr.toList()..sort();
      final idx = (p * (tmp.length - 1)).clamp(0, tmp.length - 1).floor();
      return tmp[idx];
    }

    // Per-scale robust thresholds
    final List<double> edgeThr = [
      for (final e in edgesByScale) _percentileF32(e, _edgeThrPct),
    ];

    // Skin-normalized darkness per pixel: (skin - lum)/skin
    final darkSkin = Float32List(total);
    for (int i = 0; i < total; i++) {
      darkSkin[i] = math.max(
        0.0,
        (skinN[i] - lumN[i]) / (skinN[i] + _eps),
      ); // 0..1
    }

    // DarknessScore: mean of the top percentileThreshold fraction of darkSkin
    final dsSorted = darkSkin.toList()..sort();
    final keepStart =
        (dsSorted.length * (1.0 - percentileThreshold))
            .clamp(0, dsSorted.length - 1)
            .floor();
    double darkSum = 0.0;
    final keepCount = dsSorted.length - keepStart;
    for (int i = keepStart; i < dsSorted.length; i++) {
      darkSum += dsSorted[i];
    }
    final darknessScore = (keepCount > 0 ? (darkSum / keepCount) : 0.0).clamp(
      0.0,
      1.0,
    );

    // EdgeScore: contribution per pixel, normalized by p95 and candidate count
    final contrib = Float32List(total);
    int candidateCount = 0;
    for (int i = 0; i < total; i++) {
      // strongest edge and persistence
      double eMax = 0.0;
      int persist = 0;
      for (int s = 0; s < edgesByScale.length; s++) {
        final ev = edgesByScale[s][i];
        if (ev > eMax) eMax = ev;
        if (ev > edgeThr[s]) persist++;
      }
      final persistFrac = persist / edgesByScale.length; // 0..1

      // low-saturation boost
      final satBoost = math.pow(1.0 - sats[i], saturationPower);

      // only consider pixels with some edge response AND some darkness
      if (eMax > 0.0 && darkSkin[i] > 0.0) {
        contrib[i] = eMax * darkSkin[i] * satBoost * (1.0 + 0.25 * persistFrac);
        candidateCount++;
      } else {
        contrib[i] = 0.0;
      }
    }

    // Robust normalization
    final p95 = _percentileF32(contrib, 0.95);
    double contribSum = 0.0;
    for (int i = 0; i < total; i++) {
      contribSum += contrib[i];
    }

    final edgeScore =
        (candidateCount > 0 && p95 > _eps)
            ? (contribSum / (candidateCount * p95)).clamp(0.0, 1.0)
            : 0.0;

    // Final blend (same weights you pass in)
    final score = (edgeWeight * edgeScore + darknessWeight * darknessScore)
        .clamp(0.0, 1.0);
    return score;
  }

  static double _luminance01(double r, double g, double b) {
    // Inputs in [0,1], sRGB approximate luminance
    return (0.2126 * r + 0.7152 * g + 0.0722 * b);
  }

  static double _scoreRegionWithOpenCV({
    required img.Image region,
    required int x,
    required int y,
    required int w,
    required int h,
    required double percentileThreshold, // interpret as percentile in [0..1]
    required double edgeWeight,
    required double darknessWeight,
    required double saturationPower,
    double saturationFloor = 0.2, // prevents colorful areas from wiping edges
  }) {
    // final bounds = _clampRegion(src, x, y, w, h);
    //  final region = img.copyCrop(
    //    src,
    //    x:x,
    //    y: y,
    //    width: w,
    //    height:h,
    //  );
    _storeImage(region);
    final totalPixels = w * h;
    if (totalPixels < 9) return 0.0;

    // Raw RGBA bytes from package:image
    final rgba = region.getBytes(
      order: img.ChannelOrder.rgba,
    ); // Uint8List, len = H*W*4

    cv.Mat? mat;
    cv.Mat? gray;
    cv.Mat? sobelX;
    cv.Mat? sobelY;
    cv.Mat? edgeMagnitude;
    cv.Mat? edgeNorm; // [0..1], possibly 8U or 32F depending on normalize impl
    cv.Mat? edgeNormF; // guaranteed 32F

    try {
      // Wrap RGBA into a Mat (CV_8UC4). Use the right factory for your binding.
      // If `Mat.fromList` isn't available in your version, fall back to PNG encode+imdecode.
      mat = cv.Mat.fromList(
        region.height,
        region.width,
        cv.MatType.CV_8UC4,
        rgba,
      );

      // Grayscale
      gray = cv.cvtColor(mat, cv.COLOR_RGBA2GRAY);

      // Sobel → magnitude
      sobelX = cv.sobel(gray, cv.MatType.CV_32F, 1, 0, ksize: 3);
      sobelY = cv.sobel(gray, cv.MatType.CV_32F, 0, 1, ksize: 3);
      edgeMagnitude = cv.magnitude(sobelX, sobelY); // CV_32F

      // Normalize to [0,1]
      edgeNorm = cv.normalize(
        edgeMagnitude,
        cv.Mat.empty(),
        alpha: 0,
        beta: 1,
        normType: cv.NORM_MINMAX,
      );

      // Ensure float buffer for fast reads (if already CV_32F, this is a no-op)
      edgeNormF = edgeNorm.convertTo(cv.MatType.CV_32FC1, alpha: 1.0);

      // Pull a contiguous float view of the edge map (H*W floats)
      final Uint8List edgeBytes = edgeNormF.data; // raw bytes
      final Float32List edgeBuf = edgeBytes.buffer.asFloat32List(
        edgeBytes.offsetInBytes,
        edgeBytes.lengthInBytes ~/ 4,
      );

      // Compute a percentile cutoff on edges in [0..1]
      double edgeCut = 0.0;
      if (percentileThreshold > 0.0) {
        // Copy to a simple list for percentile; for speed you could sample or use nth-element.
        final edges = List<double>.generate(edgeBuf.length, (i) => edgeBuf[i]);
        edges.sort();
        final pos = (percentileThreshold.clamp(0.0, 1.0)) * (edges.length - 1);
        final i0 = pos.floor();
        final i1 = (i0 + 1).clamp(0, edges.length - 1);
        final t = pos - i0;
        edgeCut = edges[i0] * (1.0 - t) + edges[i1] * t;
      }

      double edgeSum = 0.0;
      int darkCount = 0;

      // Walk pixels once; use RGBA for color features, edgeBuf for edge strength
      for (int yy = 0; yy < region.height; yy++) {
        final rowOff = yy * region.width;
        for (int xx = 0; xx < region.width; xx++) {
          final i = rowOff + xx;

          // RGBA channels in [0,1]
          final pOff = i * 4;
          final r = rgba[pOff] * _inv255;
          final g = rgba[pOff + 1] * _inv255;
          final b = rgba[pOff + 2] * _inv255;

          // Simple saturation proxy in [0..1]
          final maxC = r > g ? (r > b ? r : b) : (g > b ? g : b);
          final minC = r < g ? (r < b ? r : b) : (g < b ? g : b);
          final saturation = (maxC - minC) / (maxC + minC + _epsilon);
          final satBoost = math.max(
            math.pow(1.0 - saturation, saturationPower).toDouble(),
            saturationFloor,
          );

          // Darkness weights
          final lum = _luminance01(r, g, b); // [0..1]
          if (lum < 0.5) darkCount++;
          final darkWeightPx = 1.0 - lum; // [0..1]

          // Edge (already normalized [0..1])
          double e = edgeBuf[i];
          if (e < edgeCut) e = 0.0;

          edgeSum += e * darkWeightPx * satBoost;
        }
      }

      final edgeScore = (edgeSum / totalPixels).clamp(0.0, 1.0);
      final darknessScore = (darkCount / totalPixels).clamp(0.0, 1.0);

      return (edgeWeight * edgeScore + darknessWeight * darknessScore).clamp(
        0.0,
        1.0,
      );
    } finally {
      edgeNormF?.release();
      edgeNorm?.release();
      edgeMagnitude?.release();
      sobelY?.release();
      sobelX?.release();
      gray?.release();
      mat?.release();
    }
  }

  // Assuming region is cropped using `img` package
  // static Future<double> _scoreRegionWithOpenCV({
  //   required img.Image src,
  //   required int x,
  //   required int y,
  //   required int w,
  //   required int h,
  //   required double percentileThreshold,
  //   required double edgeWeight,
  //   required double darknessWeight,
  //   required double saturationPower,
  // }) async {
  //   // 1. Clamp and crop region from src as BMP/PNG or raw RGB
  //   final bounds = _clampRegion(src, x, y, w, h);
  //   final region = img.copyCrop(
  //     src,
  //     x: bounds.x0,
  //     y: bounds.y0,
  //     width: bounds.width,
  //     height: bounds.height,
  //   );
  //   final totalPixels = bounds.width * bounds.height;
  //
  //   // 2. Convert region to cv.Mat
  //   // You must convert the `region` to a Uint8List in RGBA format, and then:
  //   final regionBytes = Uint8List.fromList(
  //     img.encodePng(region),
  //   ); // or use RGBA raw buffer
  //   final mat = cv.imdecode(regionBytes, cv.IMREAD_UNCHANGED);
  //
  //   // 3. Convert to grayscale
  //   final gray = cv.cvtColor(mat, cv.COLOR_RGBA2GRAY);
  //
  //   // 4. Sobel edge detection
  //   final sobelX = cv.sobel(gray, cv.MatType.CV_32F, 1, 0, ksize: 3);
  //   final sobelY = cv.sobel(gray, cv.MatType.CV_32F, 0, 1, ksize: 3);
  //   final edgeMagnitude = cv.magnitude(sobelX, sobelY);
  //
  //   // 5. Normalize edge magnitude to [0,1]
  //   final edgeNorm = cv.normalize(
  //     edgeMagnitude,
  //     mat,
  //     alpha: 0,
  //     beta: 1,
  //     normType: cv.NORM_MINMAX,
  //   );
  //
  //   double edgeSum = 0.0;
  //   int darkCount = 0;
  //
  //   for (int yy = 0; yy < bounds.height; yy++) {
  //     for (int xx = 0; xx < bounds.width; xx++) {
  //       final i = yy * bounds.width + xx;
  //       final pixel = region.getPixel(xx, yy);
  //
  //       // Saturation calculation as before
  //       final r = pixel.r * _inv255;
  //       final g = pixel.g * _inv255;
  //       final b = pixel.b * _inv255;
  //       final maxC = math.max(r, math.max(g, b));
  //       final minC = math.min(r, math.min(g, b));
  //       final saturation = (maxC - minC) / (maxC + minC + _epsilon);
  //       final satBoost = math.pow(1.0 - saturation, saturationPower);
  //
  //       // Darkness calculation
  //       final lum = pixel.luminanceNormalized;
  //       if (lum < 0.5) darkCount++;
  //       final darkWeight = 1.0 - lum;
  //
  //       // Edge value using at method
  //       final edgeVal =
  //           await edgeNorm.at(yy, xx)
  //               as double; // Accessing pixel value at (yy, xx)
  //       edgeSum += edgeVal * darkWeight * satBoost;
  //     }
  //   }
  //
  //   final edgeScore = (edgeSum / totalPixels).clamp(0.0, 1.0);
  //   final darknessScore = (darkCount / totalPixels).clamp(0.0, 1.0);
  //
  //   return (edgeWeight * edgeScore + darknessWeight * darknessScore).clamp(
  //     0.0,
  //     1.0,
  //   );
  // }

  /// Fallback implementation with custom Sobel operator (for comparison/debugging)
  static double _scoreRegionWithCustomSobel({
    required img.Image src,
    required int x,
    required int y,
    required int w,
    required int h,
    required double percentileThreshold,
    required double edgeWeight,
    required double darknessWeight,
    required double saturationPower,
  }) {
    // Clamp region to image boundaries
    final bounds = _clampRegion(src, x, y, w, h);
    final x0 = bounds.x0, y0 = bounds.y0;
    final x1 = bounds.x1, y1 = bounds.y1;
    final ww = bounds.width, hh = bounds.height;

    if (ww < 3 || hh < 3) return 0.0;

    // Pre-allocate buffers
    final luminance = Float64List(ww * hh);
    final saturation = Float64List(ww * hh);
    final luminances = <double>[];

    // Populate buffers using optimized pixel access
    for (int j = 0; j < hh; j++) {
      for (int i = 0; i < ww; i++) {
        final pixel = src.getPixel(x0 + i, y0 + j);
        final idx = j * ww + i;

        final r = pixel.r * _inv255;
        final g = pixel.g * _inv255;
        final b = pixel.b * _inv255;

        final maxC = math.max(r, math.max(g, b));
        final minC = math.min(r, math.min(g, b));
        final sat = (maxC - minC) / (maxC + minC + _epsilon);

        final lum = pixel.luminanceNormalized * 255.0;

        luminance[idx] = lum;
        saturation[idx] = sat;
        luminances.add(lum);
      }
    }

    // Calculate adaptive threshold
    luminances.sort();
    final adaptiveThresh =
        luminances[(luminances.length * percentileThreshold).floor().clamp(
          0,
          luminances.length - 1,
        )];

    double edgeSum = 0.0;
    int darkCount = 0;

    // Apply custom Sobel operator to interior pixels
    for (int j = 1; j <= hh - 2; j++) {
      for (int i = 1; i <= ww - 2; i++) {
        final idx = j * ww + i;
        final centerLum = luminance[idx];

        final satBoost = math.pow(1.0 - saturation[idx], saturationPower);

        // 3×3 Sobel kernel
        final g00 = luminance[(j - 1) * ww + (i - 1)];
        final g01 = luminance[(j - 1) * ww + i];
        final g02 = luminance[(j - 1) * ww + (i + 1)];
        final g10 = luminance[j * ww + (i - 1)];
        final g12 = luminance[j * ww + (i + 1)];
        final g20 = luminance[(j + 1) * ww + (i - 1)];
        final g21 = luminance[(j + 1) * ww + i];
        final g22 = luminance[(j + 1) * ww + (i + 1)];

        final gx = (g02 + 2 * g12 + g22) - (g00 + 2 * g10 + g20);
        final gy = (g20 + 2 * g21 + g22) - (g00 + 2 * g01 + g02);
        final mag = math.sqrt(gx * gx + gy * gy);

        final weight = (255.0 - centerLum) * _inv255 * satBoost;
        edgeSum += mag * weight;

        if (centerLum < adaptiveThresh) darkCount++;
      }
    }

    final pixelCount = (ww - 2) * (hh - 2);
    if (pixelCount <= 0) return 0.0;

    final edgeScore = (edgeSum / (pixelCount * 255.0)).clamp(0.0, 1.0);
    final darknessScore = (darkCount / pixelCount).clamp(0.0, 1.0);

    return (edgeWeight * edgeScore + darknessWeight * darknessScore).clamp(
      0.0,
      1.0,
    );
  }

  /// Validates input parameters
  static void _validateInputs(
    img.Image? src,
    int x,
    int y,
    int w,
    int h,
    double percentileThreshold,
    double edgeWeight,
    double darknessWeight,
  ) {
    if (src == null) {
      throw ArgumentError('Source image cannot be null');
    }
    if (w <= 0 || h <= 0) {
      throw ArgumentError('Width and height must be positive');
    }
    if (percentileThreshold < 0.0 || percentileThreshold > 1.0) {
      throw ArgumentError('Percentile threshold must be between 0.0 and 1.0');
    }
    if (edgeWeight < 0.0 || edgeWeight > 1.0) {
      throw ArgumentError('Edge weight must be between 0.0 and 1.0');
    }
    if (darknessWeight < 0.0 || darknessWeight > 1.0) {
      throw ArgumentError('Darkness weight must be between 0.0 and 1.0');
    }
  }

  /// Clamps the region to image boundaries and returns adjusted coordinates
  static _RegionBounds _clampRegion(img.Image src, int x, int y, int w, int h) {
    final x0 = x.clamp(0, src.width);
    final y0 = y.clamp(0, src.height);
    final x1 = math.min(x0 + w, src.width);
    final y1 = math.min(y0 + h, src.height);

    return _RegionBounds(
      x0: x0,
      y0: y0,
      x1: x1,
      y1: y1,
      width: x1 - x0,
      height: y1 - y0,
    );
  }

  /// Scores multiple regions efficiently with optional batch processing
  static List<double> scoreMultipleRegions({
    required img.Image src,
    required List<_Region> regions,
    double percentileThreshold = _defaultPercentileThreshold,
    double edgeWeight = _defaultEdgeWeight,
    double darknessWeight = _defaultDarknessWeight,
    double saturationPower = _defaultSaturationPower,
    bool useBuiltinSobel = true,
    bool useBatchProcessing = false,
  }) {
    if (useBatchProcessing && regions.length > 1) {
      return _scoreBatchRegions(
        src: src,
        regions: regions,
        percentileThreshold: percentileThreshold,
        edgeWeight: edgeWeight,
        darknessWeight: darknessWeight,
        saturationPower: saturationPower,
        useBuiltinSobel: useBuiltinSobel,
      );
    }

    return regions
        .map(
          (region) => scoreRegion(
            src: src,
            x: region.x,
            y: region.y,
            w: region.w,
            h: region.h,
            percentileThreshold: percentileThreshold,
            edgeWeight: edgeWeight,
            darknessWeight: darknessWeight,
            saturationPower: saturationPower,
            useBuiltinSobel: useBuiltinSobel,
          ),
        )
        .toList();
  }

  /// Optimized batch processing for multiple regions
  static List<double> _scoreBatchRegions({
    required img.Image src,
    required List<_Region> regions,
    required double percentileThreshold,
    required double edgeWeight,
    required double darknessWeight,
    required double saturationPower,
    required bool useBuiltinSobel,
  }) {
    // Apply Sobel to entire image once for batch processing
    final edgeImage = useBuiltinSobel ? img.sobel(src, amount: 1.0) : null;

    return regions.map((region) {
      if (useBuiltinSobel && edgeImage != null) {
        return _scoreRegionFromPreprocessed(
          src: src,
          edgeImage: edgeImage,
          region: region,
          percentileThreshold: percentileThreshold,
          edgeWeight: edgeWeight,
          darknessWeight: darknessWeight,
          saturationPower: saturationPower,
        );
      } else {
        return scoreRegion(
          src: src,
          x: region.x,
          y: region.y,
          w: region.w,
          h: region.h,
          percentileThreshold: percentileThreshold,
          edgeWeight: edgeWeight,
          darknessWeight: darknessWeight,
          saturationPower: saturationPower,
          useBuiltinSobel: false,
        );
      }
    }).toList();
  }

  /// Scores a region from pre-processed edge image (for batch optimization)
  static double _scoreRegionFromPreprocessed({
    required img.Image src,
    required img.Image edgeImage,
    required _Region region,
    required double percentileThreshold,
    required double edgeWeight,
    required double darknessWeight,
    required double saturationPower,
  }) {
    final bounds = _clampRegion(src, region.x, region.y, region.w, region.h);
    final x0 = bounds.x0, y0 = bounds.y0;
    final ww = bounds.width, hh = bounds.height;

    if (ww < 3 || hh < 3) return 0.0;

    final luminances = <double>[];
    double weightedEdgeSum = 0.0;
    int darkCount = 0;
    int totalPixels = 0;

    // Process region pixels
    for (int j = 0; j < hh; j++) {
      for (int i = 0; i < ww; i++) {
        final srcPixel = src.getPixel(x0 + i, y0 + j);
        final edgePixel = edgeImage.getPixel(x0 + i, y0 + j);

        final r = srcPixel.r * _inv255;
        final g = srcPixel.g * _inv255;
        final b = srcPixel.b * _inv255;

        final maxC = math.max(r, math.max(g, b));
        final minC = math.min(r, math.min(g, b));
        final saturation = (maxC - minC) / (maxC + minC + _epsilon);

        final luminance = srcPixel.luminanceNormalized * 255.0;
        final edgeMagnitude = edgePixel.luminanceNormalized;

        luminances.add(luminance);

        final satBoost = math.pow(1.0 - saturation, saturationPower);
        final darknessWeight = (255.0 - luminance) * _inv255;
        final weight = darknessWeight * satBoost;

        weightedEdgeSum += edgeMagnitude * weight;
        totalPixels++;
      }
    }

    // Calculate adaptive threshold
    luminances.sort();
    final adaptiveThresh =
        luminances[(luminances.length * percentileThreshold).floor().clamp(
          0,
          luminances.length - 1,
        )];

    // Count dark pixels
    for (final lum in luminances) {
      if (lum < adaptiveThresh) darkCount++;
    }

    if (totalPixels <= 0) return 0.0;

    final edgeScore = (weightedEdgeSum / totalPixels).clamp(0.0, 1.0);
    final darknessScore = (darkCount / totalPixels).clamp(0.0, 1.0);

    return (edgeWeight * edgeScore + darknessWeight * darknessScore).clamp(
      0.0,
      1.0,
    );
  }

  /// Benchmarks both Sobel implementations to help choose the best one
  static Map<String, double> benchmark({
    required img.Image src,
    required int x,
    required int y,
    required int w,
    required int h,
    int iterations = 10,
  }) {
    final stopwatch = Stopwatch();

    // Benchmark built-in Sobel
    stopwatch.start();
    for (int i = 0; i < iterations; i++) {
      scoreRegion(src: src, x: x, y: y, w: w, h: h, useBuiltinSobel: true);
    }
    stopwatch.stop();
    final builtinTime = stopwatch.elapsedMicroseconds / iterations;

    // Benchmark custom Sobel
    stopwatch.reset();
    stopwatch.start();
    for (int i = 0; i < iterations; i++) {
      scoreRegion(src: src, x: x, y: y, w: w, h: h, useBuiltinSobel: false);
    }
    stopwatch.stop();
    final customTime = stopwatch.elapsedMicroseconds / iterations;

    return {
      'builtin_sobel_avg_microseconds': builtinTime.toDouble(),
      'custom_sobel_avg_microseconds': customTime.toDouble(),
      'speedup_factor': customTime / builtinTime,
    };
  }

  static void _storeImage(region) async {
    // 2) Encode (PNG keeps transparency; use encodeJpg for smaller files)
    final Uint8List bytes = Uint8List.fromList(img.encodePng(region));

    // 3) Pick a writable directory
    final dir = await getDownloadsDirectory(); // persistent
    // final dir = await getTemporaryDirectory(); // cache

    // 4) Write file
    final file = File('${dir!.path}/cropped_region.png');
    await file.writeAsBytes(bytes, flush: true);
  }
}

// Helper classes
class _Region {
  final int x, y, w, h;

  const _Region({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });
}

class _RegionBounds {
  final int x0, y0, x1, y1, width, height;

  const _RegionBounds({
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
    required this.width,
    required this.height,
  });
}
