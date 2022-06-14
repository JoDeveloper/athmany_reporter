import 'dart:async';
import 'dart:developer';

import 'package:sqflite/sqflite.dart';

class DBService {
  final Database db;

  DBService(this.db);

  Future<Map> getProfileDetails() async {
    const sql = '''SELECT * FROM pos_profile_details''';
    try {
      final data = await db.rawQuery(sql);
      log(data[0].toString(), name: 'profile details');
      return data[0];
    } on Exception catch (e) {
      log(e.toString());
    }
    return {};
  }
}
