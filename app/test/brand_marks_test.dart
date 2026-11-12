import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/profile/brand_marks.dart';

/// The wallet page's and Connected tools' logos draw from their own path
/// data, nothing fetched.
void main() {
  for (final brand in ['ethereum', 'solana', 'metamask', 'jupiter', 'uniswap', 'definitive']) {
    testWidgets('$brand draws', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Center(child: BrandMark(brand, size: 38))));
      expect(tester.takeException(), isNull);
      expect(find.byType(BrandMark), findsOneWidget);
    });
  }
}
