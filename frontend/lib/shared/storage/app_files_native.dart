import 'dart:io';

import 'package:path_provider/path_provider.dart';

export 'dart:io'
    show
        Directory,
        File,
        FileSystemEntity,
        FileSystemEntityType,
        FileSystemException;

Future<String?> initializeAppStorage() async => null;

Future<Directory> applicationSupportDirectory() =>
    getApplicationSupportDirectory();
