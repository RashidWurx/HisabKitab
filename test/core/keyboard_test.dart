import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/core/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('Save stays above the keyboard and closes it', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var saved = false;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(focusNode: focus, autofocus: true),
          bottomNavigationBar: SaveBar(
            label: 'Save',
            onPressed: () => saved = true,
          ),
        ),
      ),
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pump();

    expect(
      tester.getRect(find.byType(FilledButton)).bottom,
      lessThanOrEqualTo(800 - 320),
    );
    expect(find.byTooltip('Hide keyboard'), findsOneWidget);
    expect(focus.hasFocus, isTrue);

    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(saved, isTrue);
    expect(focus.hasFocus, isFalse);
  });
}
