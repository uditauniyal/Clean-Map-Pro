import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttertoast/fluttertoast.dart';

class AddPostScreen extends StatefulWidget {
  const AddPostScreen({Key? key}) : super(key: key);

  @override
  _AddPostScreenState createState() => _AddPostScreenState();
}

class _AddPostScreenState extends State<AddPostScreen> {
  Uint8List? _file;
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _locationController = TextEditingController(); // Location controller
  String _priority = 'Low';
  bool _isLoading = false;

  Future<Uint8List?> pickImage(ImageSource source) async {
    final ImagePicker _picker = ImagePicker();
    XFile? pickedFile = await _picker.pickImage(source: source);

    if (pickedFile != null) {
      return await pickedFile.readAsBytes();
    }
    return null;
  }

  @override
  void dispose() {
    super.dispose();
    _descriptionController.dispose();
  }

  void postImage() async {
    if (_file == null) {
      Fluttertoast.showToast(msg: "No image selected");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Fluttertoast.showToast(msg: "No user found!");
      setState(() {
        _isLoading = false;
      });
      return;
    }

   try {
      String imageUrl = await uploadImageToStorage(_file!);
      await FirebaseFirestore.instance.collection('posts').add({
        'description': _descriptionController.text,
        'location': _locationController.text, // Include location data
        'imageUrl': imageUrl,
        'uid': user.uid,
        'username': user.displayName,
        'userImage': user.photoURL,
        'datePublished': DateTime.now(),
        'priority': _priority,
        'picked': 0,
      });

      Fluttertoast.showToast(msg: "Posted successfully!");
      Navigator.pop(context);
    } catch (e) {
      Fluttertoast.showToast(msg: "Failed to post: ${e.toString()}");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<String> uploadImageToStorage(Uint8List file) async {
    Reference ref = FirebaseStorage.instance
        .ref()
        .child('posts')
        .child(FirebaseAuth.instance.currentUser!.uid);

    UploadTask uploadTask = ref.putData(file);
    TaskSnapshot snap = await uploadTask;
    String downloadUrl = await snap.ref.getDownloadURL();
    return downloadUrl;
  }

  void selectImage() async {
    Uint8List? file = await pickImage(ImageSource.gallery);
    if (file != null) {
      setState(() {
        _file = file;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Add Post"),
        actions: [
          TextButton(
            onPressed: postImage,
            child: Text(
              "Post",
              style: TextStyle(
                color: Colors.blueAccent,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView( // Wrap with SingleChildScrollView for scrollable content
        child: Column(
          children: [
            _isLoading ? LinearProgressIndicator() : SizedBox.shrink(),
            _file != null
              ? Image.memory(_file!, height: 200, width: double.infinity, fit: BoxFit.cover) // Image preview
              : IconButton(
                  icon: Icon(Icons.image),
                  onPressed: selectImage,
                ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: TextField(
                controller: _descriptionController,
                decoration: InputDecoration(hintText: "Write a caption..."),
                maxLines: null,
              ),
             
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: TextField(
                controller: _locationController,
                decoration: InputDecoration(hintText: "Enter location..."),
              ),
            ),
            DropdownButton<String>(
              value: _priority,
              onChanged: (String? newValue) {
                setState(() {
                  _priority = newValue!;
                });
              },
              items: <String>['Low', 'Moderate', 'High']
                  .map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}