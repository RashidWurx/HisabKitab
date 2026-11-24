import 'package:material_ui/material_ui.dart';

/// Temporary screen shown until a feature is built in a later phase.
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(
          '$title is coming in a later phase.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}
