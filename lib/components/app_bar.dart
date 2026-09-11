import 'package:contractor_hub/components/reusable_icon_button.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:contractor_hub/providers/auth_provider.dart';

class AppBarWidget extends StatelessWidget implements PreferredSizeWidget {
  const AppBarWidget({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 30);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      elevation: 10,
      backgroundColor: Colors.grey[600],
      centerTitle: true,
      automaticallyImplyLeading: false,
      title: const Text(
        'Chat Job',
        style: TextStyle(fontSize: 20, color: Colors.black),
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
                  Navigator.pushNamed(context, '/homePage');
                },
                icon: Icon(Icons.home),
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
                icon: Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
