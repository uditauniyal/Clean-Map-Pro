import 'dart:async';
import 'dart:io';
import 'package:camera_app/Mainscreen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';  
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart'; // The Auth Service file you just created
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_google_maps_webservices/places.dart';
import 'package:google_maps_place_picker_mb/google_maps_place_picker.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';







// Import any other necessary packages here



class ThemeManager extends ChangeNotifier {
  bool _isDarkMode = false;

  bool get isDarkMode => _isDarkMode;

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }
}


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
 await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
);
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  String? token = await FirebaseMessaging.instance.getToken();
  print("Firebase Messaging Token: $token");
  // To handle messages while the app is in the foreground
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print("Message received. Title: ${message.notification?.title}, Body: ${message.notification?.body}");
    // Here, you can also show a notification using a package like flutter_local_notifications
  });

  Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("Handling a background message: ${message.messageId}");
}

// Then set the background message handler
FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);


  runApp(
    MyApp()
  );
}


class MyApp extends StatelessWidget {
  MyApp();

  Future<CameraDescription> _initializeCamera() async {
    final cameras = await availableCameras();
    return cameras.first; // Assuming a camera is available
  }

  Future<String?> _getUserTypeFromFirestore() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      FirebaseFirestore firestore = FirebaseFirestore.instance;
      DocumentReference userDoc = firestore.collection('users').doc(user.uid);

      DocumentSnapshot userSnapshot = await userDoc.get();
      if (userSnapshot.exists) {
        Map<String, dynamic> userData = userSnapshot.data() as Map<String, dynamic>;
        return userData['userType'];
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ThemeManager(),
      child: Consumer<ThemeManager>(
        builder: (context, themeManager, child) {
          return MaterialApp(
            theme: themeManager.isDarkMode ? ThemeData.dark() : ThemeData.light(),
            home: FutureBuilder<CameraDescription>(
              future: _initializeCamera(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                  return StreamBuilder<User?>(
                    stream: AuthService().authStateChanges,
                    builder: (context, userSnapshot) {
                      if (userSnapshot.connectionState == ConnectionState.active) {
                        if (userSnapshot.data == null) {
                          return SignInScreen(camera: snapshot.data!);
                        } else {
                          return FutureBuilder<String?>(
                            future: _getUserTypeFromFirestore(),
                            builder: (context, userTypeSnapshot) {
                              if (userTypeSnapshot.connectionState == ConnectionState.done) {
                                switch (userTypeSnapshot.data) {
                                  case 'municipality':
                                    return MunicipalityScreen();
                                  case 'community':
                                    return CameraApp(camera: snapshot.data!, userType: userTypeSnapshot.data);
                                  default:
                                    return SelectUserTypeScreen(camera: snapshot.data!);
                                }
                              }
                              return CircularProgressIndicator();
                            },
                          );
                        }
                      }
                      return CircularProgressIndicator();
                    },
                  );
                }
                return CircularProgressIndicator();
              },
            ),
          );
        },
      ),
    );
  }
}



class SignInScreen extends StatelessWidget {
  final CameraDescription camera;

  SignInScreen({required this.camera});

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  Future<void> _signInWithGoogle(BuildContext context) async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // User cancelled the Google Sign-in process
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await _auth.signInWithCredential(credential);

      // Navigate to the CameraApp on successful sign-in
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
      builder: (context) => SelectUserTypeScreen(camera: camera),
    ),
      );
    } catch (error) {
      print('Google Sign-In Error: $error');
      // Optionally, show an error message to the user
    }
  }


  Future<void> _registerWithEmailPassword(BuildContext context) async {
  try {
    final UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
      email: _emailController.text,
      password: _passwordController.text,
    );

    if (userCredential.user != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
        builder: (context) => SelectUserTypeScreen(camera: camera),
        ),
      );
    }
  } on FirebaseAuthException catch (e) {
    String errorMessage = 'An error occurred. Please try again.';
    
    if (e.code == 'weak-password') {
      errorMessage = 'The password provided is too weak. It should be at least 6 characters.';
    } else if (e.code == 'email-already-in-use') {
      errorMessage = 'An account already exists for that email.';
    } else if (e.code == 'invalid-email') {
      errorMessage = 'The email address is not valid.';
    }

    // Display the error message
    _showErrorDialog(context, errorMessage);
  } catch (e) {
    print('Error: $e');
    // Optionally, show a generic error message to the user
  }
}

void _showErrorDialog(BuildContext context, String message) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Authentication Error'),
      content: Text(message),
      actions: <Widget>[
        TextButton(
          child: Text('Okay'),
          onPressed: () {
            Navigator.of(ctx).pop();
          },
        )
      ],
    ),
  );
}




 @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Sign In')),
      
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(  
                controller: _emailController,
                decoration: InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
              SizedBox(height: 20),
              ElevatedButton.icon(
                icon: Icon(Icons.login),
                label: Text('Sign up with Email'),
                onPressed: () => _registerWithEmailPassword(context),
              ),
              SizedBox(height: 20),
              ElevatedButton.icon(
                icon: Icon(Icons.login),
                label: Text('Sign in with Google'),
                onPressed: () => _signInWithGoogle(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class CameraApp extends StatefulWidget {
  final CameraDescription camera;
  final String? userType; // Make userType optional

  const CameraApp({Key? key, required this.camera, this.userType}) : super(key: key);

  @override
  _CameraAppState createState() => _CameraAppState();
}


class _CameraAppState extends State<CameraApp> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  Timer? _timer;
  List<String> imagePaths = [];
  List<String> detectedClasses = []; // Store detected classes
  Position? currentPosition; // Store current position
  bool _isCapturing = false;
  bool _isLoading = false;
  String userType = 'community'; // Default to 'community'

// Function to save image data to Firebase Firestore
Future<void> saveImageDataToFirebase(Map<String, dynamic> imageData) async {
  FirebaseFirestore firestore = FirebaseFirestore.instance;
  CollectionReference wasteCollection = firestore.collection('wasteData');

  // Save the data map directly to a new document
  await wasteCollection.add(imageData);
} 


Future<String> uploadImageToFreeImageHost(String imagePath) async {
  var uri = Uri.parse('https://freeimage.host/api/1/upload');
  var request = http.MultipartRequest('POST', uri)
    ..fields['key'] = '6d207e02198a847aa98d0a2a901485a5'
    ..fields['action'] = 'upload'
    ..fields['format'] = 'json'
    ..files.add(await http.MultipartFile.fromPath('source', imagePath));

  var response = await request.send();
  if (response.statusCode == 200) {
    var responseData = await response.stream.toBytes();
    var responseString = String.fromCharCodes(responseData);
    var jsonResponse = json.decode(responseString);

    if (jsonResponse['status_code'] == 200) {
      return jsonResponse['image']['url'];
    } else {
      throw Exception('Failed to upload image to Freeimage.host');
    }
  } else {
    throw Exception('Failed to upload image to Freeimage.host');
  }
}



Future<void> _captureAndSaveImageData() async {
  try {
    setState(() {
      _isLoading = true;
    });

    // Capture the image
    final image = await _controller.takePicture();
    
    // Get the current position
    final currentPosition = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    
    // Upload the image and get its URL
    final String imageUrl = await uploadImageAndGetUrl(image.path);
    
    final String imageurl2 = await uploadImageToFreeImageHost(image.path);
    print(imageurl2);

    // Get the classes from the API using the view URL
    final List<String> classes = await sendImageToApiAndGetClasses(imageurl2);
    print(classes);
    // Save the image data to Firebase
 
    await saveImageDataToFirebase({
      'imageUrl': imageUrl,
      'latitude': currentPosition.latitude,
      'longitude': currentPosition.longitude,
      'tags': classes,
      'statusPicked': 0,
    });
    

    // Update the UI
    setState(() {
      _isLoading = false;
      imagePaths.add(image.path);
      detectedClasses.addAll(classes);
    });

    // Show success toast
    Fluttertoast.showToast(
      msg: "Image Uploaded Successfully!",
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 1,
    );
  } catch (e) {
    setState(() {
      _isLoading = false;
    });
  

    // Show error toast
    Fluttertoast.showToast(
      msg: "Failed to upload image: $e",
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 3,
    );

    print('Error capturing and saving image data: $e');
  }
}
  // Function to retrieve and show saved entries
  // Function to retrieve and show saved entries
Future<void> _showSavedEntries(BuildContext context) async {
    try {
      // Fetch data from Firebase
      FirebaseFirestore firestore = FirebaseFirestore.instance;
      QuerySnapshot querySnapshot = await firestore.collection('wasteData').get();

      List<Map<String, dynamic>> entries = querySnapshot.docs.map((doc) {
        return doc.data() as Map<String, dynamic>;
      }).toList();

      // Show the entries in a dialog or new screen
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Garbage detected'),
            content: SingleChildScrollView(
              child: ListBody(
                children: entries.map((entry) {
                  String? imageUrl = entry['imageUrl'];
                  double latitude = entry['latitude'] as double? ?? 0.0;
                  double longitude = entry['longitude'] as double? ?? 0.0;
                  List<String> tags = List<String>.from(entry['tags'] ?? []);
                  int statusPicked = entry['statusPicked'] as int? ?? 0;

                  return Card(
                    child: ListTile(
                      leading: imageUrl != null && imageUrl.isNotEmpty
                               ? Image.network(
                                   imageUrl, 
                                   width: 50, 
                                   height: 50, 
                                   fit: BoxFit.cover,
                                   loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
                                     if (loadingProgress == null) return child;
                                     return SizedBox(
                                       width: 50,
                                       height: 50,
                                       child: Center(child: CircularProgressIndicator()),
                                     );
                                   },
                                   errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
                                     // Replace 'assets/error_image.png' with your local asset's path
                                     return Image.asset('assets/error_image.png', width: 50, height: 50);
                                   },
                                 )
                               : Image.asset('assets/error_image.png', width: 50, height: 50), // Default error image
                      title: Text('Location: $latitude, $longitude'),
                      subtitle: Text('Tags: ${tags.join(', ')}\nStatus Picked: ${statusPicked == 1 ? "Yes" : "No"}'),
                    ),
                  );
                }).toList(),
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: Text('Close'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    } catch (e) {
      print('Error fetching saved entries: $e');
      // Optionally, show an error message to the user
    }
  }


Future<void> _logout(BuildContext context) async {
  try {
    // Sign out from Google Sign-In
    final GoogleSignIn _googleSignIn = GoogleSignIn();
    await _googleSignIn.signOut();

    // Sign out from Firebase Auth
    await FirebaseAuth.instance.signOut();

    // Navigate to the sign-in screen
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => SignInScreen(camera: widget.camera),
      ),
    );
  } catch (e) {
    print('Error signing out: $e');
    // Optionally, show an error message to the user
  }
}


  void _getUserType() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? storedUserType = prefs.getString('userType');
    if (storedUserType != null) {
      setState(() {
        userType = storedUserType;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _getCurrentLocation();
     userType = widget.userType ?? userType;// Get current location
  }

  void _initializeCamera() async {
    // Use a try-catch block to handle potential errors
    try {
      // Select a widely supported resolution
      final ResolutionPreset resolution = ResolutionPreset.medium;

      _controller = CameraController(widget.camera, ResolutionPreset.low);
      _initializeControllerFuture = _controller.initialize();
       if (mounted) {
      setState(() {});
    }
  } catch (e) {
    print('Error initializing camera: $e');
    // Optionally, show an error message to the user
  }
      // Check if the controller is initialized
    //   if (_controller.value.hasError) {
    //     print('Camera error: ${_controller.value.errorDescription}');
    //   }
    // } catch (e) {
    //   print('Error initializing camera: $e');
    // }
  }

  @override
  void dispose() {
    _controller.dispose();
    _timer?.cancel();
    super.dispose();
  }

  // Function to capture image and send to API
 void _captureImagePeriodically() {
  const period = Duration(seconds: 5);
  _timer = Timer.periodic(period, (Timer t) async {
    if (!_controller.value.isInitialized) {
      print('Camera not initialized');
      return;
    }

    try {
      await _initializeControllerFuture;
      // Instead of calling takePicture directly, call the method to handle capture and save
      await _captureAndSaveImageData();
    } catch (e) {
      print('Error capturing image: $e');
    }
  });
}

void _toggleCapturing() {
    if (_isCapturing) {
      _timer?.cancel();
    } else {
      _captureImagePeriodically();
    }

    setState(() {
      _isCapturing = !_isCapturing;
    });
  }
  // Function to get current location
  void _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled. Request user to enable it.
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied. Show a message.
        return Future.error('Location permissions are denied');
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      // Permissions are permanently denied. Show a message.
      return Future.error(
          'Location permissions are permanently denied. We cannot request permissions.');
    } 

    // When we reach here, permissions are granted and we can continue accessing the position.
    currentPosition = await Geolocator.getCurrentPosition();
  }

  // Function to upload image and get URL (needs implementation)



Future<String> uploadImageAndGetUrl(String imagePath) async {
  File imageFile = File(imagePath);
  String fileName = "images/${DateTime.now().millisecondsSinceEpoch}_${imageFile.path.split('/').last}";

  // Get a reference to the Firebase Storage instance
  FirebaseStorage storage = FirebaseStorage.instance;

  // Create a reference to the file location
  Reference ref = storage.ref().child(fileName);

  // Start the upload task
  UploadTask uploadTask = ref.putFile(imageFile);

  // Wait for the upload to complete
  await uploadTask;

  // Get the download URL
  String downloadUrl = await ref.getDownloadURL();

  return downloadUrl;
}

  // Function to send image to API and get classes (needs implementation)


Future<List<String>> sendImageToApiAndGetClasses(String imageUrl) async {
  setState(() {
      _isLoading = true; // Set loading to true
    });
  var url = Uri.parse("https://reciclapi-garbage-detection.p.rapidapi.com/predict");
  var payload = json.encode({ "image": imageUrl });
  //0fe4a749eemshd01fe1029abda27p156c80jsn677e337944c
  //8e8dd3656dmshd6333e4be9ab810p1d0d1cjsn5cccc959a8fa
  var headers = {
    "content-type": "application/json",
    "X-RapidAPI-Key": "bb169364a9mshe95f5274be978abp1e9ab9jsn55fa77d674f2",
    "X-RapidAPI-Host": "reciclapi-garbage-detection.p.rapidapi.com"
  };

  var response = await http.post(url, body: payload, headers: headers);
   setState(() {
      _isLoading = false; // Set loading to false once data is fetched
    });
  if (response.statusCode == 200) {
    var jsonResponse = json.decode(response.body) as List;
    List<String> classes = jsonResponse.map((item) => item['class'].toString()).toList();
    return classes;
  } else {
    throw Exception('Failed to load data from API');
  }
}

@override
Widget build(BuildContext context) {
  // Assuming FirebaseAuth.instance.currentUser is not null
  final user = FirebaseAuth.instance.currentUser!;
  final themeManager = Provider.of<ThemeManager>(context, listen: false);

  return Scaffold(
    appBar: AppBar(
      title: Text('🗺️CleanMapPro'),
    
     actions: [
          CircleAvatar(
            backgroundImage: NetworkImage(user.photoURL ?? 'default_image_url'),
            radius: 20,
          ),
          Switch(
            value: themeManager.isDarkMode,
            onChanged: (newValue) {
              themeManager.toggleTheme();
            },
          ),
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
      ],
    ),
    body: Stack( // Use Stack to overlay camera preview and GridView
      children: [
        FutureBuilder<void>(
          future: _initializeControllerFuture,
          builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (snapshot.hasError) {
              // Handle the error state
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            return CameraPreview(_controller); // Full-screen camera preview
          } else {
            return Center(child: CircularProgressIndicator());
          }

          },
        ),
        Align( // Align GridView to the bottom of the screen
          alignment: Alignment.bottomCenter,
          child: Container(
            padding: const EdgeInsets.only(bottom: 50), // Adjust the padding as needed
            height: MediaQuery.of(context).size.height * 0.3, // Adjust the height as needed
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
              ),
              itemCount: imagePaths.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.all(4.0), // Add padding around each image
                  child: Image.file(File(imagePaths[index])),
                );
              },
            ),
          ),
        ),
      ],
    ),
    
    floatingActionButton: Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            FloatingActionButton(
              onPressed: _toggleCapturing,
              tooltip: 'Capture Images',
              child: Icon(_isCapturing ? Icons.stop : Icons.camera_alt),
            ),
            FloatingActionButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => MainScreen()),
                );
              },
              tooltip: 'Create Post',
              child: Icon(Icons.group),
            ),
            FloatingActionButton(
              onPressed: () => _showSavedEntries(context),
              tooltip: 'Show Saved Entries',
              child: Icon(Icons.list),
            ),
            FloatingActionButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => MapSample()),
                );
              },
              tooltip: 'Show Map',
              child: Icon(Icons.map),
            ),
            FloatingActionButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ShowWasteIndex()),
                );
              },
              tooltip: 'Waste index',
              child: Icon(Icons.forest),
            ),
          ],
        ),
      ),
    ),
    floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
  );
}


}

class MapSample extends StatefulWidget {
  @override
  State<MapSample> createState() => MapSampleState();
}


class MapSampleState extends State<MapSample> {
  late GoogleMapController googleMapController;
  Set<Marker> markers = {};
  Set<Circle> circles = {};

  @override
  void initState() {
    super.initState();
    _fetchMarkerData();
  }

Future<void> _fetchMarkerData() async {
  try {
    FirebaseFirestore firestore = FirebaseFirestore.instance;
    QuerySnapshot querySnapshot = await firestore.collection('wasteData').get();
    
    Set<Marker> tempMarkers = {};
    Map<LatLng, int> markerDensity = {};

    for (var doc in querySnapshot.docs) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      if (data['latitude'] != null && data['longitude'] != null) {
        LatLng markerPosition = LatLng(data['latitude'], data['longitude']);
        tempMarkers.add(
          Marker(
            markerId: MarkerId(doc.id),
            position: markerPosition,
            onTap: () => _showMarkerDetailsDialog(context, data),
          ),
        );
        markerDensity.update(markerPosition, (value) => value + 1, ifAbsent: () => 1);
      }
    }

    Set<Circle> tempCircles = {};
    markerDensity.forEach((position, density) {
      Color circleColor;
      if (density > 2) {
        circleColor = Colors.red.withOpacity(0.2);
      } else if (density >= 1 && density <= 2) {
        circleColor = Colors.yellow.withOpacity(0.2);
      } else {
        circleColor = Colors.green.withOpacity(0.2);
      }

      tempCircles.add(
        Circle(
          circleId: CircleId(position.toString()),
          center: position,
          radius: 2000, // 5 km
          fillColor: circleColor,
          strokeWidth: 1,
          strokeColor: circleColor,
        ),
      );
    });

    setState(() {
      markers = tempMarkers;
      circles = tempCircles;
    });
  } catch (e) {
    print("Error fetching markers: $e");
  }
}


void _showMarkerDetailsDialog(BuildContext context, Map<String, dynamic> data) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text("Trash details"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            data['imageUrl'] != null
                ? Image.network(data['imageUrl'])
                : SizedBox(),
            Text("Coordinates: ${data['latitude']}, ${data['longitude']}"),
            Text("Tags: ${(data['tags'] as List).join(', ')}"),
            Text("Status Picked: ${data['statusPicked'] == 1 ? "Yes" : "No"}"),
          ],
        ),
        actions: <Widget>[
          TextButton(
            child: Text('Close'),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
}

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CleanMapPro locate',
      home: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text('CleanMapPro locate'),
        ),
        body: SizedBox(
          width: double.infinity,
          height: MediaQuery.of(context).size.height,
          child: GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: CameraPosition(
              target:LatLng(28.6312, 77.3709),
              zoom: 12,
            ),
            onMapCreated: (GoogleMapController controller) {
              googleMapController = controller;
            },
            markers: markers,
          circles: circles,
          ),
        ),
      ),
    );
  }
}


class SelectUserTypeScreen extends StatefulWidget {
  final CameraDescription camera;

  SelectUserTypeScreen({required this.camera});

  @override
  _SelectUserTypeScreenState createState() => _SelectUserTypeScreenState();
}

class _SelectUserTypeScreenState extends State<SelectUserTypeScreen> {
  String userType = 'community'; // Default user type

  void _handleUserTypeChange(String? value) {
    if (value != null) {
      setState(() {
        userType = value;
      });
    }
  }

  void _setUserTypeAndProceed() async {
  User? user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    // Get a reference to the Firestore instance and the user's document
    FirebaseFirestore firestore = FirebaseFirestore.instance;
    DocumentReference userDoc = firestore.collection('users').doc(user.uid);

    // Set the user type in the user's document
    await userDoc.set({'userType': userType}, SetOptions(merge: true));

    // Navigate to CameraApp with userType
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => CameraApp(camera: widget.camera, userType: userType),
      ),
    );
  } else {
    // Handle the case when the user is not logged in
    print('User not logged in');
  }
}


void _getUserType() async {
  User? user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    FirebaseFirestore firestore = FirebaseFirestore.instance;
    DocumentReference userDoc = firestore.collection('users').doc(user.uid);

    // Retrieve the user document
    DocumentSnapshot userSnapshot = await userDoc.get();
    if (userSnapshot.exists) {
      Map<String, dynamic> userData = userSnapshot.data() as Map<String, dynamic>;
      setState(() {
        userType = userData['userType'] ?? 'community'; // Default to 'community' if not set
      });
    }
  } else {
    // Handle the case when the user is not logged in
    print('User not logged in');
  }
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Select User Type'),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ListTile(
            title: const Text('Community'),
            leading: Radio<String>(
              value: 'community',
              groupValue: userType,
              onChanged: _handleUserTypeChange,
            ),
          ),
          ListTile(
            title: const Text('Municipality'),
            leading: Radio<String>(
              value: 'municipality',
              groupValue: userType,
              onChanged: _handleUserTypeChange,
            ),
          ),
          ElevatedButton(
            onPressed: _setUserTypeAndProceed,
            child: Text('Continue'),
          ),
        ],
      ),
    );
  }
}

class MunicipalityScreen extends StatefulWidget {
  @override
  _MunicipalityScreenState createState() => _MunicipalityScreenState();
}

class _MunicipalityScreenState extends State<MunicipalityScreen> {
  TextEditingController _searchController = TextEditingController();
  LatLng _currentPosition = LatLng(0, 0); // Default position
   GoogleMapsPlaces _places = GoogleMapsPlaces(apiKey: "AIzaSyCLAUzFkqMIdcowRHtBuzEmQPZUMTDYaRY"); // Replace with your API Key
  String _currentLocation = 'No location selected';
  bool _isLoading = false;
  

Future<void> pickAndUploadImage(String wasteDataId) async {
  final ImagePicker _picker = ImagePicker();
  XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);

  if (pickedFile != null) {
    Uint8List fileData = await pickedFile.readAsBytes();
    String imageUrl = await uploadImageToStorage(fileData);
    await FirebaseFirestore.instance.collection('wasteData').doc(wasteDataId).update({
      'pickedImage': imageUrl,
      'statusPicked': 1,
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


  Future<void> _logout(BuildContext context) async {
    try {
      final GoogleSignIn _googleSignIn = GoogleSignIn();
      await _googleSignIn.signOut();
      await FirebaseAuth.instance.signOut();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => MyApp()), // MyApp is your root widget
        (Route<dynamic> route) => false,
      );
    } catch (e) {
      print('Error signing out: $e');
    }
  }


void _launchMapsUrl(double lat, double lng) async {
  final url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
  if (await canLaunch(url)) {
    await launch(url);
  } else {
    throw 'Could not launch $url';
  }
}





  void _detectCurrentLocation() async {
    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
    });
    print('Current location: $_currentPosition');
  }


  Future<String> getAddress(double latitude, double longitude) async {
  final url = 'https://geocode.maps.co/reverse?lat=$latitude&lon=$longitude&api_key=65d0b3e646ab0353188447tyscf55fc';

  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);
      return responseData['display_name'] ?? 'Unknown address';
    } else {
      return 'Unknown address';
    }
  } catch (e) {
    return 'Error fetching address';
  }
}



  Future<String> getAddressFromLatLng(double latitude, double longitude) async {
  final String apiKey = 'AIzaSyCLAUzFkqMIdcowRHtBuzEmQPZUMTDYaRY'; // Replace with your API key
  final String url = 'https://maps.googleapis.com/maps/api/geocode/json?latlng=$latitude,$longitude&key=$apiKey';

  try {
    final response = await http.get(Uri.parse(url));
    print(response.body);
    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);
      // Extract the formatted address
      if (responseData['results'] != null && responseData['results'].length > 0) {
        return responseData['results'][0]['formatted_address'];
      } else {
        return 'Unknown location';
      }
    } else {
      print('Failed to fetch the address');
      return 'Unknown location';
    }
  } catch (e) {
    print('Error occurred: $e');
    return 'Unknown location';
  }
}


@override
void initState() {
  super.initState();
 
}



@override
void dispose() {
  _searchController.dispose();
  super.dispose();
}
 @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final themeManager = Provider.of<ThemeManager>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: Text('🗺️CleanMapPro'),
        actions: [
          CircleAvatar(
            backgroundImage: NetworkImage(user.photoURL ?? 'default_image_url'),
            radius: 20,
          ),
          SizedBox(width: 10),
          Switch(
            value: themeManager.isDarkMode,
            onChanged: (newValue) {
              themeManager.toggleTheme();
            },
          ),
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
        ],
      ),
 body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _showSavedEntries(context),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(child: Text('No entries found'));
          } else {
            return ListView.builder(
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                var entry = snapshot.data![index];
                String docId = entry['WasteDataId']; 
                double latitude = entry['latitude'] as double? ?? 0.0;
                double longitude = entry['longitude'] as double? ?? 0.0;
                List<String> tags = List<String>.from(entry['tags'] ?? []);
                int statusPicked = entry['statusPicked'] as int? ?? 0;
                String imageUrl = entry['imageUrl'] ?? 'default_image_url'; 

                Future<String> address = getAddressFromLatLng(latitude, longitude);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            
            children: [
              // Leading Image
              ClipRRect(
                
                borderRadius: BorderRadius.circular(8.0),
                child: Image.network(
                  imageUrl,
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Image.asset('path_to_default_image', width: 50, height: 50);
                  },
                ),
              ),
              SizedBox(width: 10),

              // Expanded to handle text and buttons
              Expanded(
                child: Column(
                  
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    
                    Text('Latitude: $latitude, Longitude: $longitude'),
                    Text('Tags: ${tags.join(', ')}'),
                    Text('Status Picked: ${statusPicked == 1 ? "Yes" : "No"}'),
                    Spacer(),
                    Row(
 children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _launchMapsUrl(latitude, longitude),
                            child: Text('Directions'),
                          ),
                        ),
                        SizedBox(width: 8),
                        if (statusPicked == 0)
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => pickAndUploadImage(docId),
                              child: Text('Mark as Picked'),
                            ),
                          ),
                      ],
),

                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    
  },
  
);
  
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => MapSample()),
          );
        },
        child: Icon(Icons.map),
      ),
    );
  }
Future<List<Map<String, dynamic>>> _showSavedEntries(BuildContext context) async {
  try {
    FirebaseFirestore firestore = FirebaseFirestore.instance;
    QuerySnapshot querySnapshot = await firestore.collection('wasteData').get();

    // Create a list of maps from the documents
    List<Map<String, dynamic>> entries = querySnapshot.docs.map((doc) {
      // Add the document ID to the map
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      data['WasteDataId'] = doc.id; // Add the Firestore document ID to the map
      return data;
    }).toList();

    return entries;
  } catch (e) {
    print('Error fetching saved entries: $e');
    throw e; // Rethrow the exception
  }
}






}


class LocationSearchScreen extends StatefulWidget {
  @override
  _LocationSearchScreenState createState() => _LocationSearchScreenState();
}



class _LocationSearchScreenState extends State<LocationSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final GoogleMapsPlaces _places = GoogleMapsPlaces(apiKey: 'AIzaSyCLAUzFkqMIdcowRHtBuzEmQPZUMTDYaRY'); // Use your API key
  List<Prediction> _predictions = [];

  void _onSearchChanged(String search) async {
    if (search.isNotEmpty) {
      final res = await _places.autocomplete(search);
      if (res.isOkay && mounted) {
        setState(() => _predictions = res.predictions);
      }
    } else {
      setState(() => _predictions = []);
    }
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => _onSearchChanged(_controller.text));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Select Your Location')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Search for location...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                suffixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _predictions.length,
              itemBuilder: (context, index) {
                final prediction = _predictions[index];
                return ListTile(
                  leading: Icon(Icons.location_on),
                  title: Text(prediction.description ?? 'No description available'),
                  onTap: () {
                    // Handle the location selection
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}



class MapScreen extends StatefulWidget {
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late GoogleMapController mapController;
  final LatLng _initialPosition = LatLng(37.77483, -122.41942); // San Francisco

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  void _showPlacePicker() async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlacePicker(
          apiKey: "AIzaSyCLAUzFkqMIdcowRHtBuzEmQPZUMTDYaRY", // Add your own API key here
          onPlacePicked: (result) {
            // Handle the selected place result
            print(result.formattedAddress);
            Navigator.of(context).pop(); // Dismiss the place picker
          },
          initialPosition: _initialPosition,
          useCurrentLocation: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Map Screen'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextFormField(
              readOnly: true, // Prevents the keyboard from showing on tap
              onTap: _showPlacePicker,
              decoration: InputDecoration(
                hintText: 'Search for location...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[400]!),
                ),
              ),
            ),
          ),
          Expanded(
            child: GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: CameraPosition(
                target: _initialPosition,
                zoom: 11.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class ShowWasteIndex extends StatefulWidget {
  @override
  ShowWasteIndexState createState() => ShowWasteIndexState();
}

class ShowWasteIndexState extends State<ShowWasteIndex> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;
  double wasteIndex = 0.0;
  int pickedCount = 0;
  int unpickedCount = 0;
  int totalCount = 0;
  Color zoneColor = Colors.green; // Default color

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    calculateWasteIndex();
  }

  Future<void> calculateWasteIndex() async {
    Position currentPosition = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

    FirebaseFirestore firestore = FirebaseFirestore.instance;
    QuerySnapshot querySnapshot = await firestore.collection('wasteData').get();

    int localDensity = 0;
    querySnapshot.docs.forEach((doc) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      double latitude = data['latitude'];
      double longitude = data['longitude'];
      int statusPicked = data['statusPicked'];

      double distance = Geolocator.distanceBetween(
        currentPosition.latitude, currentPosition.longitude,
        latitude, longitude
      );

      if (distance <= 2000) { // Within 2 km radius
        localDensity++;
        if (statusPicked == 1) {
          pickedCount++;
        } else {
          unpickedCount++;
        }
      }

      totalCount++;
    });

    setState(() {
      wasteIndex = (localDensity / 10).clamp(0.0, 10.0);
      if (wasteIndex > 8) {
        zoneColor = Colors.red;
      } else if (wasteIndex > 5) {
        zoneColor = Colors.yellow;
      } else {
        zoneColor = Colors.green;
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Waste Index"),
      ),
      body: Center(
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                double opacity = _animation.value;
                double size = 150.0 + (50.0 * _animation.value);

                return Opacity(
                  opacity: opacity,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: zoneColor.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  "Waste Index: ${wasteIndex.toStringAsFixed(1)}/10",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                Text(
                  "Picked: $pickedCount",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                Text(
                  "Unpicked: $unpickedCount",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                Text(
                  "Total: $totalCount",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }




}