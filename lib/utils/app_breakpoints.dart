abstract final class AppBreakpoints {
  static const mobile = 600.0;
  static const desktop = 900.0;
  static const wideDesktop = 1440.0;
  static const contentMaxWidth = 1040.0;
  static bool isDesktop(double width) => width >= desktop;
  static int gridColumns(double width) => width >= 1000
      ? 3
      : width >= 620
      ? 2
      : 1;
}
