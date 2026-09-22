import 'package:flutter/material.dart';

class ResponsivePage extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  const ResponsivePage({
    super.key,
    required this.child,
    this.maxWidth = 900,
    this.padding = const EdgeInsets.symmetric(
      horizontal: 20,
      vertical: 18,
    ),
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxWidth,
                  minWidth: 0,
                ),
                child: Padding(
                  padding: padding,
                  child: child,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
