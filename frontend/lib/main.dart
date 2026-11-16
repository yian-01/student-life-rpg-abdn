import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/cloud/cloud_sync_controller.dart';
import 'app/student_life_app.dart';
import 'shared/storage/app_files.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storageError = await initializeAppStorage();
  if (storageError != null) {
    runApp(
      MaterialApp(
        title: 'Student Life RPG',
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(storageError, textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
    return;
  }
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
  final cloud = CloudSyncController();
  await cloud.initialize();
  runApp(
    StudentLifeApp(cloud: cloud, openAccountPage: kIsWeb && cloud.session == null),
  );
}
