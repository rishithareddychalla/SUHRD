import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'emergency_contacts.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/'),
        ),
        title: const Text(
          'Emergency Numbers',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0XFFF52324A),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: emergencyContacts.length,
              itemBuilder: (context, index) {
                final contact = emergencyContacts[index];
                return ListTile(
                  title: Text(
                    contact['name']!,
                    style: TextStyle(
                      color: Colors.grey[800],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    contact['phone']!,
                    style: TextStyle(color: Colors.grey[900]),
                  ),
                );
              },
            ),
          ),
          // <-- pushes logo to bottom
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Image.asset(
              'assets/images/sgito_360.png', // place your logo file here
              height: 60, // adjust size
            ),
          ),
        ],
      ),
    );
  }
}
