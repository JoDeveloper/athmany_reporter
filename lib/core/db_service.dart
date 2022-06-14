import 'dart:async';
import 'dart:developer';

import 'package:sqflite/sqflite.dart';

class DBService {
  final Database db;

  DBService(this.db);

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
