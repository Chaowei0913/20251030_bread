import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FriendsListPage extends StatelessWidget {
  const FriendsListPage({super.key});
  Future<void> _removeFriend(
      BuildContext context,
      String myUid,
      String friendUid,
      ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除好友'),
        content: const Text('確定要刪除此好友嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final firestore = FirebaseFirestore.instance;

      final myRef = firestore.collection('users').doc(myUid);
      final friendRef = firestore.collection('users').doc(friendUid);

      await firestore.runTransaction((transaction) async {
        transaction.update(myRef, {
          'friends': FieldValue.arrayRemove([friendUid]),
        });
        transaction.update(friendRef, {
          'friends': FieldValue.arrayRemove([myUid]),
        });
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 已移除好友')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ 移除失敗：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('請先登入')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('好友列表')),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data =
          snapshot.data!.data() as Map<String, dynamic>;
          final List friends = data['friends'] ?? [];

          if (friends.isEmpty) {
            return const Center(child: Text('尚無好友'));
          }

          return ListView.builder(
            itemCount: friends.length,
            itemBuilder: (context, index) {
              final friendUid = friends[index];

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(friendUid)
                    .get(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const ListTile(
                      title: Text('載入中...'),
                    );
                  }

                  final friendData =
                  snapshot.data!.data() as Map<String, dynamic>;

                  return ListTile(
                    leading: const Icon(Icons.person),
                    title: Text(friendData['name']),
                    subtitle: Text(friendData['email']),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        _removeFriend(
                          context,
                          user.uid,
                          friendUid,
                        );
                      },
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}