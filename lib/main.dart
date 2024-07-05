import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:simple_shadow/simple_shadow.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:starsview/config/StarsConfig.dart';
import 'package:starsview/starsview.dart';
import 'package:starsview/config/MeteoriteConfig.dart';
import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    return NeumorphicApp(
      title: 'LED Controller',
      themeMode: ThemeMode.dark,
      theme: NeumorphicThemeData(
        baseColor: Color(0xFFFFFFFF),
        lightSource: LightSource.topLeft,
        depth: 10,
      ),
      darkTheme: NeumorphicThemeData(
        baseColor: Color(0xFF09061A),
        lightSource: LightSource.topLeft,
        shadowLightColor: Color.fromARGB(255, 19, 13, 53),
        shadowDarkColor: Color.fromARGB(255, 2, 2, 7),
        depth: 8,
      ),
      home: MyHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  BluetoothConnection? connection;
  double intensity = 1.0;
  bool isConnected = false;
  bool isOn = true;
  Timer? _timer;
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _startConnectionCheck();
    _initializeNotifications();
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    final InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> _requestPermissions() async {
    var status = await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location
    ].request();

    if (status[Permission.bluetooth]!.isGranted &&
        status[Permission.bluetoothConnect]!.isGranted &&
        status[Permission.bluetoothScan]!.isGranted &&
        status[Permission.location]!.isGranted) {
      // Permisos concedidos
    } else {
      print("Permisos no concedidos");
    }
  }

  Future<void> _connectToDevice() async {
    try {
      var devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      for (var device in devices) {
        if (device.name == "ESP32") {
          connection = await BluetoothConnection.toAddress(device.address);
          setState(() {
            isConnected = true;
          });
          break;
        }
      }
      if (!isConnected) {
        print("No se encontró el dispositivo");
      }
    } catch (e) {
      print("Error connecting to device: $e");
    }
  }

  void _sendData(String command) {
    if (connection != null && connection!.isConnected) {
      connection!.output.add(Uint8List.fromList(utf8.encode(command)));
    }
  }

  void _toggleLed() {
    if (isOn) {
      _sendData("OFF\n");
      _cancelNotification();
      sendNotification(deviceToken, 'LED', 'El LED se ha apagado');
    } else {
      _sendData("ON\n");
      _showNotification();
      sendNotification(deviceToken, 'LED', 'El LED se ha encendido');
    }
    setState(() {
      isOn = !isOn;
    });
  }

  Future<void> _showNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'your_channel_id',
      'your_channel_name',
      channelDescription: 'your_channel_description',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
      enableVibration: false,
      chronometerCountDown: true,
      icon: '@mipmap/launcher_icon',
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(
      0,
      'LED',
      'El LED se ha encendido',
      platformChannelSpecifics,
    );
  }

  Future<void> _cancelNotification() async {
    await flutterLocalNotificationsPlugin.cancel(0);
  }

  void _startConnectionCheck() {
    _timer = Timer.periodic(Duration(seconds: 2), (timer) {
      if (connection != null) {
        setState(() {
          isConnected = connection!.isConnected;
        });
      } else {
        setState(() {
          isConnected = false;
        });
      }
    });
  }

  final String serviceAccountFile =
      'assets/wear-7484f-firebase-adminsdk-y8951-40d336b7bb.json';
  final String projectId = 'wear-7484f';
  final String deviceToken =
      'clnlT7SoQYa5xDbrRDLIsk:APA91bFhfp19FEZ2UriUgCaGlqBEuNqA8oGKekjnJNdrki35yAEzCUHRBgDBIt0dd5fNyXqpdgFhgGyLL9_PItK-4t3xsAGDRE9RRDi-M-9-RvU3ubcNXMw1_1UbnmIWiHEha1pvXMQP';

  Future<String> getAccessToken() async {
    var accountCredentials = ServiceAccountCredentials.fromJson(
      await DefaultAssetBundle.of(context).loadString(serviceAccountFile),
    );
    var scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
    var authClient = await clientViaServiceAccount(accountCredentials, scopes);
    var token = (await authClient.credentials).accessToken.data;
    authClient.close();
    return token;
  }

  Future<void> sendNotification(String token, String title, String body) async {
    var accessToken = await getAccessToken();
    var headers = {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json; charset=UTF-8',
    };
    var payload = {
      'message': {
        'token': token,
        'notification': {
          'title': title,
          'body': body,
        },
        'android': {
          'priority': 'high',
          'notification': {
            'notification_priority': 'priority_high',
            'default_vibrate_timings': 'true',
          },
        },
        "webpush": {
          'headers': {"Urgency": "high"}
        },
        'data': {
          'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          'id': '1',
          'status': 'done'
        }
      }
    };

    var response = await http.post(
      Uri.parse(
          'https://fcm.googleapis.com/v1/projects/$projectId/messages:send'),
      headers: headers,
      body: json.encode(payload),
    );

    if (response.statusCode == 200) {
      print('Notification sent successfully');
    } else {
      print('Failed to send notification');
      print(response.body);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NeumorphicTheme.baseColor(context),
      body: Stack(
        children: <Widget>[
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color.fromARGB(255, 5, 4, 16),
                  Color.fromARGB(255, 6, 4, 19),
                  Color.fromARGB(255, 9, 6, 26),
                  Color.fromARGB(255, 18, 12, 52),
                ],
              ),
            ),
          ),
          StarsView(
            fps: 60,
            starsConfig: StarsConfig(minStarSize: 0, maxStarSize: 2),
            meteoriteConfig: MeteoriteConfig(enabled: false),
          ),
          Container(
            width: double.infinity,
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                isConnected
                    ? isOn
                        ? SimpleShadow(
                            sigma: 19,
                            color: Color.fromARGB(255, 255, 214, 0),
                            opacity: 1,
                            offset: Offset(0, 0),
                            child: IconButton(
                              icon: Image.asset(
                                "assets/images/foco.png",
                                height: 100,
                                color: Color.fromARGB(255, 255, 214, 0),
                              ),
                              onPressed: _toggleLed,
                            ),
                          )
                        : IconButton(
                            icon: Image.asset(
                              "assets/images/foco.png",
                              height: 100,
                            ),
                            onPressed: _toggleLed,
                          )
                    : Text(
                        'Sin conexión',
                        style: TextStyle(
                            color: Color.fromARGB(255, 255, 255, 255),
                            fontSize: 15),
                      ),
                SizedBox(height: 40),
                NeumorphicButton(
                  onPressed: _connectToDevice,
                  child: isConnected ? Text('Desconectar') : Text('Conectar'),
                  style: NeumorphicStyle(
                      boxShape: NeumorphicBoxShape.roundRect(
                          BorderRadius.circular(10))),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    connection?.dispose();
    super.dispose();
  }
}
