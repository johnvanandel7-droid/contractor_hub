
import 'package:contractor_hub/components/reusable_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:contractor_hub/providers/auth_provider.dart';
 
class AppBarWidget extends StatelessWidget implements PreferredSizeWidget {
  // Optional: AppBarWidget(title: 'To Do List') shows the current page name.
  final String? title;
 
  const AppBarWidget({super.key, this.title});
 
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 30);
 
  void _snack(ScaffoldMessengerState messenger, String text) {
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }
 
  Future<void> _confirmAndSignOut(BuildContext context) async {
    // Grab everything we need from context BEFORE any await.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
 
    final AuthProvider auth;
    try {
      auth = context.read<AuthProvider>();
    } catch (e) {
      debugPrint('Logout: AuthProvider lookup failed: $e');
      _snack(messenger,
          'Logout failed: AuthProvider is not provided above this screen. ($e)');
      return;
    }
 
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
 
    try {
      await auth.signOut();
    } catch (e) {
      debugPrint('Logout: signOut threw: $e');
      _snack(messenger, 'Could not sign out: $e');
      return;
    }
 
    try {
      navigator.pushNamedAndRemoveUntil('/welcomeScreen', (route) => false);
    } catch (e) {
      debugPrint('Logout: navigation failed: $e');
      _snack(messenger,
          "Signed out, but couldn't open /welcomeScreen (is the route registered?): $e");
    }
  }
 
  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);
 
    return AppBar(
      elevation: 2,
      backgroundColor: Colors.blueGrey[800],
      foregroundColor: Colors.white,
      centerTitle: true,
      automaticallyImplyLeading: false,
      leading: canPop
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
              onPressed: () => Navigator.pop(context),
            )
          : null,
      title: Text(
        title ?? 'Contractor Hub',
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(30),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ReusableIconButton(
                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/homePage',
                  (route) => false,
                ),
                icon: const Icon(Icons.home),
              ),
              ReusableIconButton(
                onPressed: () => _confirmAndSignOut(context),
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
        ),
      ),
    );
  }
}