import 'package:catcher/model/platform_type.dart';
import 'package:flutter/foundation.dart';

import '../handlers/stack_trace_handler.dart';

class Report {
  /// Error that has been caught
  final dynamic error;

  /// Stack trace of error
  final StackTrace stackTrace;

  /// Time when it was caught
  final DateTime dateTime;

  /// Device info
  final Map<String, dynamic> deviceParameters;

  /// Application info
  final Map<String, dynamic> applicationParameters;

  /// Custom parameters passed to report
  final Map<String, dynamic> customParameters;

  /// FlutterErrorDetails data if present
  final FlutterErrorDetails? errorDetails;

  /// Type of platform used
  final PlatformType platformType;

  /// Creates report instance
  Report(
    this.error,
    this.stackTrace,
    this.dateTime,
    this.deviceParameters,
    this.applicationParameters,
    this.customParameters,
    this.errorDetails,
    this.platformType,
  );

  String get functionNameWithCaller => CustomTrace(stackTrace).functionName ?? "" "()";

  /// Creates json from current instance
  Map<String, dynamic> toJson({
    bool enableDeviceParameters = true,
    bool enableApplicationParameters = true,
    bool enableStackTrace = true,
    bool enableCustomParameters = false,
  }) {
    final Map<String, dynamic> json = <String, dynamic>{
      "error": CustomTrace(stackTrace).toString(),
      "customParameters": customParameters,
      "dateTime": dateTime.toIso8601String(),
      "platformType": describeEnum(platformType),
    };
    if (enableDeviceParameters) {
      json["deviceParameters"] = deviceParameters;
    }
    if (enableApplicationParameters) {
      json["applicationParameters"] = applicationParameters;
    }
    if (enableStackTrace) {
      json["stackTrace"] = CustomTrace(stackTrace).toString();
      json['method'] = CustomTrace(stackTrace).functionName;
    }
    if (enableCustomParameters) {
      json["customParameters"] = customParameters;
    }
    return json;
  }
}
