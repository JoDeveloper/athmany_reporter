import 'dart:async';
import 'dart:developer';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

const _uri = "/api/method/business_layer.pos_business_layer.doctype.pos_error_log.pos_error_log.new_pos_error_log";

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

  Future<String?> getSavedBaseUrl() async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final baseUrl = sharedPreferences.get('base_url') as String;
    return baseUrl + _uri;
  }
}
