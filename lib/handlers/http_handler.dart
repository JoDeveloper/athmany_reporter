import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:catcher/core/db_service.dart';
import 'package:catcher/model/http_request_type.dart';
import 'package:catcher/model/platform_type.dart';
import 'package:catcher/model/report.dart';
import 'package:catcher/model/report_handler.dart';
import 'package:catcher/utils/catcher_utils.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';

import '../model/cached_request.dart';

const _uri = "/api/method/business_layer.pos_business_layer.doctype.pos_error_log.pos_error_log.new_pos_error_log";

class HttpHandler extends ReportHandler {
  final Dio dio;
  final HttpRequestType requestType;
  final Map<String, dynamic> headers;
  final int requestTimeout;
  final int responseTimeout;
  final bool printLogs;
  final bool enableDeviceParameters;
  final bool enableApplicationParameters;
  final bool enableStackTrace;
  final bool enableCustomParameters;
  final DBService dbService;

  HttpHandler(
    this.requestType,
    this.dio,
    this.dbService, {
    Map<String, dynamic>? headers,
    this.requestTimeout = 5000,
    this.responseTimeout = 5000,
    this.printLogs = false,
    this.enableDeviceParameters = true,
    this.enableApplicationParameters = true,
    this.enableStackTrace = true,
    this.enableCustomParameters = false,
  }) : headers = headers ?? <String, dynamic>{};

  @override
  Future<bool> handle(Report error, BuildContext? context) async {
    if (error.platformType != PlatformType.web) {
      if (!(await CatcherUtils.isInternetConnectionAvailable())) {
        _printLog("No internet connection available");
        return false;
      }
    }

    if (requestType == HttpRequestType.post) {
      return _sendPost(error);
    }
    return true;
  }

  Future<bool> _sendPost(Report report) async {
    CachedRequest? cachedrequest;
    try {
      final profile = await dbService.getProfileDetails();

      final data = {
        "method": report.toJson()['methodName'],
        "pos_profile": profile['name'],
        "date_time": DateTime.now().toIso8601String(),
        "error": report.functionNameWithCaller,
      };
      cachedrequest = CachedRequest(url: _uri, body: Body.fromJson(data));
      final HashMap<String, dynamic> mutableHeaders = HashMap<String, dynamic>();
      if (headers.isNotEmpty == true) {
        mutableHeaders.addAll(headers);
      }

      final Options options = Options(
        sendTimeout: requestTimeout,
        receiveTimeout: responseTimeout,
        headers: mutableHeaders,
      );

      Response? response;
      {
        response = await dio.post(_uri, data: data, options: options);
      }
      _printLog(
        "HttpHandler response status: ${response.statusCode!} body: ${response.data!}",
      );
      return true;
    } on SocketException catch (e) {
      _cacheThRequest(cachedrequest);
      _printLog("HttpHandler SocketException: $e");
      return false;
    } on TimeoutException catch (e) {
      _cacheThRequest(cachedrequest);
      _printLog("HttpHandler TimeoutException: $e");
      return false;
    } catch (error, stackTrace) {
      _printLog("HttpHandler error: $error, stackTrace: $stackTrace");
      return false;
    }
  }

  void _printLog(String log) {
    if (printLogs) {
      logger.info(log);
    }
  }

  @override
  String toString() {
    return 'HttpHandler';
  }

  @override
  List<PlatformType> getSupportedPlatforms() => [
        PlatformType.android,
        PlatformType.iOS,
        PlatformType.web,
        PlatformType.linux,
        PlatformType.macOS,
        PlatformType.windows,
      ];

  void _cacheThRequest(CachedRequest? cachedRequest) {
    if (cachedRequest != null) {
      final cache = GetStorage();

      final cachedRequestString = cache.read<String?>("cachedRequests");

      final cachedRequests = cachedRequestString != null ? cachedRequestFromJson(cachedRequestString) : <CachedRequest>[];

      cachedRequests.add(cachedRequest);

      cache.write("cachedRequests", cachedRequestToJson(cachedRequests));
    }
  }
}
