import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final TextEditingController _emailController = TextEditingController();
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email']);
  User? user = FirebaseAuth.instance.currentUser;

  Future<void> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth =
      await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );

      final userCredential =
      await FirebaseAuth.instance.signInWithCredential(credential);

      user = userCredential.user;

      await _createUserDocumentIfNotExists(user!);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 登入成功')),
      );
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ 登入失敗: $e')),
      );
    }
  }

  Future<void> _createUserDocumentIfNotExists(User user) async {
    final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final docSnapshot = await userDoc.get();

    if (!docSnapshot.exists) {
      await userDoc.set({
        'name': user.displayName ?? '匿名',
        'email': user.email ?? '',
        'friends': [], // 好友陣列
      });
      debugPrint('✅ Firebase users document 已建立: ${user.uid}');
    } else {
      debugPrint('ℹ️ Firebase users document 已存在: ${user.uid}');
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await FirebaseAuth.instance.signOut();
    setState(() {
      user = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已登出')),
    );
  }

  Future<void> sendFriendRequest() async {  //好友申請
    final email = _emailController.text.trim();

    if (email.isEmpty || user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請輸入 Email')),
      );
      return;
    }

    try {
      // 1️⃣ 用 email 找使用者
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ 找不到此使用者')),
        );
        return;
      }

      final targetDoc = query.docs.first;
      final targetUid = targetDoc.id;

      // 2️⃣ ❌ 不能加自己
      if (targetUid == user!.uid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ 不能加自己為好友')),
        );
        return;
      }

      // 3️⃣ ❌ 檢查是否已經是好友
      final myDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();

      final List friends = myDoc.data()?['friends'] ?? [];
      if (friends.contains(targetUid)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ 你們已經是好友了')),
        );
        return;
      }

      // 4️⃣ 新增好友邀請
      await FirebaseFirestore.instance.collection('friend_requests').add({
        'fromUid': user!.uid,
        'toUid': targetUid,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      _emailController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 好友邀請已送出')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ 發生錯誤：$e')),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('朋友列表')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (user == null)
              ElevatedButton.icon(
                onPressed: signInWithGoogle,
                icon: const Icon(Icons.login),
                label: const Text('使用 Google 登入'),
              )
            else ...[
              Text('已登入: ${user!.displayName}'),
              const SizedBox(height: 20),

              // 🔹 輸入好友 Email 的輸入框
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: TextField(
                  controller: _emailController, // ⭐ 就是我們剛剛新增的變數
                  decoration: const InputDecoration(
                    labelText: '輸入好友 Email',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              ElevatedButton(
                onPressed: sendFriendRequest,
                child: const Text('新增好友'),
              ),

              const SizedBox(height: 20),

              ElevatedButton.icon(
                onPressed: signOut,
                icon: const Icon(Icons.logout),
                label: const Text('登出'),
              ),
            ]
          ],
        ),
      ),
    );
  }
}