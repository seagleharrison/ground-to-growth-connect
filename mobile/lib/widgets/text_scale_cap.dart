import 'package:flutter/widgets.dart';

/// The most the phone's "larger text" setting is allowed to grow text in this
/// app. People who need big text still get it (1.6 times is large), but
/// beyond this the dense screens stop fitting a phone.
const double kMaxTextScale = 1.6;

/// Applies the cap to everything below it.
Widget capTextScale(Widget child) => Builder(
      builder: (context) => MediaQuery.withClampedTextScaling(maxScaleFactor: kMaxTextScale, child: child),
    );
