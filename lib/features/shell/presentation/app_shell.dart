import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../transactions/presentation/quick_add_sheet.dart';

/// Bottom navigation: Home, Activity, Dues, Subscriptions, More.
/// The centre "+" (quick add) shows on Home, Activity and Dues.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final showFab = shell.currentIndex <= 2;
    return Scaffold(
      body: shell,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: showFab
          ? Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: FloatingActionButton(
                heroTag: 'quick-add',
                onPressed: () => showQuickAddSheet(context),
                child: const Icon(Icons.add, size: 30),
              ),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        labelPadding: EdgeInsets.zero,
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Icon(Icons.handshake_outlined),
            selectedIcon: Icon(Icons.handshake),
            label: 'Dues',
          ),
          NavigationDestination(
            icon: Icon(Icons.autorenew),
            label: 'Subscriptions',
          ),
          NavigationDestination(icon: Icon(Icons.menu), label: 'More'),
        ],
      ),
    );
  }
}
