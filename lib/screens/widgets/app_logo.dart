import 'package:flutter/material.dart';

/// Which logo to show.
///   mark  the main logo (welcome screen)
///   auth  logo2, for Sign In and Create Account
enum AppLogoVariant { mark, auth }

/// The ANTHROFIT logo, matched to the theme: the original files are drawn
/// for dark backgrounds, the _v2 files for light ones.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 88, this.variant = AppLogoVariant.mark});

  /// Height of the logo. The width follows the image's own shape.
  final double size;
  final AppLogoVariant variant;

  static String assetFor(AppLogoVariant variant, Brightness brightness) {
    final light = brightness == Brightness.light;
    return switch (variant) {
      AppLogoVariant.mark => light
          ? 'assets/logo/anthrofit_logo_v2.png'
          : 'assets/logo/anthrofit_logo.png',
      AppLogoVariant.auth => light
          ? 'assets/logo/anthrofit_logo2_v2.png'
          : 'assets/logo/anthrofit_logo2.png',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Image.asset(
        assetFor(variant, Theme.of(context).brightness),
        height: size,
        semanticLabel: 'ANTHROFIT logo',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        // Large source image: decode it at the size it is shown.
        cacheHeight: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      ),
    );
  }
}
