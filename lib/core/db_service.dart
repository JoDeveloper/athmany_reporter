// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DBService {
  final Database db;

  DBService(this.db);

  // get database path
  Future<String> getDatabasePath(String dbName) async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, dbName);
    log(path);

    //make sure the folder exists
    if (await Directory(dirname(path)).exists()) {
      log('dir exists');
    } else {
      await Directory(dirname(path)).create(recursive: true);
      log('dir created');
    }
    return path;
  }

  // configure
  FutureOr onConfigure(Database db) async {
    // Add support for cascade delete
    await db.execute("PRAGMA foreign_keys = ON");
  }

  // on create
  Future<void> onCreate(Database db, int version) async {}

  Future<Map> getCompanyDetails() async {
    const sql = '''SELECT * FROM company_details''';
    try {
      final data = await db.rawQuery(sql);
      log(data[0].toString(), name: 'company details');
      return data[0];
    } on Exception catch (e) {
      log(e.toString());
    }
    return {};
  }
}
