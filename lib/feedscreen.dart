import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'dart:typed_data';

// Define the web screen size for responsive design
const double webScreenSize = 600;

// Define color variables
const Color webBackgroundColor = Colors.grey;
const Color mobileBackgroundColor = Colors.white;
const Color primaryColor = Colors.blue;

class PostCard extends StatelessWidget {
  final Map<String, dynamic> snap;
  final String postId;

  const PostCard({Key? key, required this.snap, required this.postId}) : super(key: key);

  Future<void> pickAndUploadImage() async {
    final ImagePicker _picker = ImagePicker();
    XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      String imageUrl = await uploadImageToStorage(await pickedFile.readAsBytes());
      await FirebaseFirestore.instance.collection('posts').doc(postId).update({
        'pickedImage': imageUrl,
        'picked': 1,
      });
      Fluttertoast.showToast(msg: "Image updated successfully!");
    }
  }

  Future<String> uploadImageToStorage(Uint8List file) async {
    Reference ref = FirebaseStorage.instance
        .ref()
        .child('pickedImages')
        .child(FirebaseAuth.instance.currentUser!.uid);

    UploadTask uploadTask = ref.putData(file);
    TaskSnapshot snap = await uploadTask;
    String downloadUrl = await snap.ref.getDownloadURL();
    return downloadUrl;
  }

 @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: snap['userImage'] != null
                ? CircleAvatar(
                    backgroundImage: NetworkImage(snap['userImage']),
                    radius: 20,
                  )
                : CircleAvatar(
                    radius: 20,
                    child: CircularProgressIndicator(),
                  ),
            title: Text(snap['username'] ?? 'Anonymous'),
          ),
          Text(snap['description'] ?? 'No description'),
          if (snap['imageUrl'] != null)
            Image.network(
              snap['imageUrl'],
              loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(child: CircularProgressIndicator());
              },
              errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
                return Text('Error loading image');
              },
            ),
          Text('Location: ${snap['location'] ?? 'Not specified'}'),
          if (snap['picked'] == 0)
            TextButton(
              onPressed: pickAndUploadImage,
              child: Text("Mark as Picked"),
            )
          else
            Column(
              children: [
                Text("Status: Picked ✅"),
                if (snap['pickedImage'] != null)
                  Image.network(
                    snap['pickedImage'],
                    height: 100,
                    width: 100,
                    fit: BoxFit.cover,
                    loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(child: CircularProgressIndicator());
                    },
                    errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
                      return Text('Error loading image');
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class FeedScreen extends StatelessWidget {
  const FeedScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: width > webScreenSize ? null : AppBar(
        backgroundColor: width > webScreenSize ? webBackgroundColor : mobileBackgroundColor,
        centerTitle: false,
        title: SvgPicture.asset(
          'assets/ic_instagram.svg',
          color: primaryColor,
          height: 32,
        ),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.messenger_outline,
              color: primaryColor,
            ),
          ),
        ],
      ),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance
            .collection('posts')
            .orderBy('datePublished', descending: true)
            .snapshots(),
            
        builder: (context, AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No data available'));
          }

          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var doc = snapshot.data!.docs[index];
              return Container(
                margin: EdgeInsets.symmetric(
                  horizontal: width > webScreenSize ? width * 0.3 : 0,
                  vertical: width > webScreenSize ? 15 : 0,
                ),
                child: PostCard(
                  snap: doc.data(),
                  postId: doc.id,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
