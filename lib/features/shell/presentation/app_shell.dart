import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Bottom navigation: Home, Activity, Dues, Subscriptions, More.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
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
          NavigationDestination(
            icon: Icon(Icons.menu),
            label: 'More',
          ),
        ],
      ),
    );
  }
}
