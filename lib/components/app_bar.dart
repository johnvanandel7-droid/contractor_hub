
import 'package:contractor_hub/components/reusable_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:contractor_hub/providers/auth_provider.dart';
 
class AppBarWidget extends StatelessWidget implements PreferredSizeWidget {
  // Optional: pass e.g. AppBarWidget(title: 'To Do List') from a screen to
  // show what page you're on instead of the static app name everywhere.
  // Existing call sites with no argument keep working unchanged.
  final String? title;
 
  const AppBarWidget({super.key, this.title});
 
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 30);
 
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
                onPressed: () {
                  // Clears back to Home instead of pushing another copy on
                  // top when Home is tapped while already on Home, or stacks
                  // of screens deep.
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/homePage',
                    (route) => false,
                  );
                },
                icon: const Icon(Icons.home),
              ),
              ReusableIconButton(
                onPressed: () async {
                  await context.read<AuthProvider>().signOut();
                  if (!context.mounted) return;
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/welcomeScreen',
                    (route) => false,
                  );
                },
                // Was Icons.close, which reads as "dismiss" rather than
                // "sign out" — logout is the unambiguous choice here.
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
        ),
      ),
    );
  }
}