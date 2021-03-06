import 'dart:async';

import 'package:catcher/catcher.dart';
import 'package:catcher/core/application_profile_manager.dart';
import 'package:catcher/model/platform_type.dart';
import 'package:catcher/utils/catcher_error_widget.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite/sqlite_api.dart';
import 'package:stack_trace/stack_trace.dart';

import '../model/cached_request.dart';
import 'db_service.dart';

// const _uri = "https://alqimma.athmany.tech";

class AthmanyCatcher with ReportModeAction {
  static late AthmanyCatcher _instance;
  static GlobalKey<NavigatorState>? _navigatorKey;

  /// Root widget which will be ran
  final Widget? appWidget;

  final Database database;

  late DBService _dbService;

  late Dio dio;

  ///Run app function which will be ran
  final void Function()? runAppFunction;

  /// Instance of catcher config used in release mode
  CatcherOptions? releaseConfig;

  /// Instance of catcher config used in debug mode
  CatcherOptions? debugConfig;

  /// Instance of catcher config used in profile mode
  CatcherOptions? profileConfig;

  /// Should catcher logs be enabled
  final bool enableLogger;

  /// Should catcher run WidgetsFlutterBinding.ensureInitialized() during initialization.
  final bool ensureInitialized;

  late CatcherOptions _currentConfig;
  late CatcherLogger _logger;
  final Map<String, dynamic> _deviceParameters = <String, dynamic>{};
  final Map<String, dynamic> _applicationParameters = <String, dynamic>{};
  final List<Report> _cachedReports = [];
  final Map<DateTime, String> _reportsOcurrenceMap = {};
  LocalizationOptions? _localizationOptions;

  /// Instance of navigator key
  static GlobalKey<NavigatorState>? get navigatorKey {
    return _navigatorKey;
  }

  /// Builds catcher instance
  AthmanyCatcher({
    this.appWidget,
    required this.runAppFunction,
    required this.database,
    required this.dio,
    this.releaseConfig,
    this.debugConfig,
    this.profileConfig,
    this.enableLogger = false,
    this.ensureInitialized = false,
    GlobalKey<NavigatorState>? navigatorKey,
  }) : assert(
          appWidget != null || runAppFunction != null,
          "You need to provide rootWidget or runAppFunction",
        ) {
    _configure(navigatorKey);
  }

  void _configure(GlobalKey<NavigatorState>? navigatorKey) async {
    _instance = this;
    _dbService = DBService(database);
    await GetStorage.init();
    _configureNavigatorKey(navigatorKey);
    _setupCurrentConfig();
    _configureLogger();
    _setupErrorHooks();
    _setupReportModeActionInReportMode();
    _loadDeviceInfo();
    _loadApplicationInfo();

    if (_currentConfig.handlers.isEmpty) {
      _logger.warning(
        "Handlers list is empty. Configure at least one handler to "
        "process error reports.",
      );
    } else {
      _logger.fine("Catcher configured successfully.");
    }
    Connectivity().onConnectivityChanged.listen((result) {
      if (result == ConnectivityResult.mobile || result == ConnectivityResult.wifi) {
        _sendCachedReports();
      }
    });
  }

  void _configureNavigatorKey(GlobalKey<NavigatorState>? navigatorKey) {
    if (navigatorKey != null) {
      _navigatorKey = navigatorKey;
    } else {
      _navigatorKey = GlobalKey<NavigatorState>();
    }
  }

  Future<void> _setupCurrentConfig() async {
    _currentConfig = CatcherOptions(
      SilentReportMode(),
      [
        if (enableLogger) ConsoleHandler(),
        HttpHandler(
          HttpRequestType.post,
          dio,
          _dbService,
        ),
      ],
    );
  }

  ///Update config after initialization
  void updateConfig({
    CatcherOptions? debugConfig,
    CatcherOptions? profileConfig,
    CatcherOptions? releaseConfig,
  }) {
    if (debugConfig != null) {
      this.debugConfig = debugConfig;
    }
    if (profileConfig != null) {
      this.profileConfig = profileConfig;
    }
    if (releaseConfig != null) {
      this.releaseConfig = releaseConfig;
    }
    _setupCurrentConfig();
    _setupReportModeActionInReportMode();
    _configureLogger();
    _localizationOptions = null;
  }

  void _setupReportModeActionInReportMode() {
    _currentConfig.reportMode.setReportModeAction(this);
    _currentConfig.explicitExceptionReportModesMap.forEach(
      (error, reportMode) {
        reportMode.setReportModeAction(this);
      },
    );
  }

  void _setupLocalizationsOptionsInReportMode() {
    _currentConfig.reportMode.setLocalizationOptions(_localizationOptions);
    _currentConfig.explicitExceptionReportModesMap.forEach(
      (error, reportMode) {
        reportMode.setLocalizationOptions(_localizationOptions);
      },
    );
  }

  void _setupLocalizationsOptionsInReportsHandler() {
    for (var handler in _currentConfig.handlers) {
      handler.setLocalizationOptions(_localizationOptions);
    }
  }

  Future _setupErrorHooks() async {
    FlutterError.onError = (FlutterErrorDetails details) async {
      Zone.current.handleUncaughtError(details.exception, details.stack!);
      _reportError(details.exception, details.stack, errorDetails: details);
    };

    if (appWidget != null) {
      _runZonedGuarded(() {
        runApp(appWidget!);
      });
    } else if (runAppFunction != null) {
      _runZonedGuarded(() {
        Chain.capture(() {
          runAppFunction!();
        });
      });
    } else {
      throw ArgumentError("Provide rootWidget or runAppFunction to Catcher.");
    }
  }

  void _runZonedGuarded(void Function() callback) {
    runZonedGuarded<Future<void>>(() async {
      if (ensureInitialized) {
        WidgetsFlutterBinding.ensureInitialized();
      }
      callback();
    }, (dynamic error, StackTrace stackTrace) {
      _reportError(error, stackTrace);
    });
  }

  void _configureLogger() {
    if (_currentConfig.logger != null) {
      _logger = _currentConfig.logger!;
    } else {
      _logger = CatcherLogger();
    }
    if (enableLogger) {
      _logger.setup();
    }

    for (var handler in _currentConfig.handlers) {
      handler.logger = _logger;
    }
  }

  void _loadDeviceInfo() {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (ApplicationProfileManager.isWeb()) {
      deviceInfo.webBrowserInfo.then((webBrowserInfo) {
        _loadWebParameters(webBrowserInfo);
        _removeExcludedParameters();
      });
    } else if (ApplicationProfileManager.isLinux()) {
      deviceInfo.linuxInfo.then((linuxDeviceInfo) {
        _loadLinuxParameters(linuxDeviceInfo);
        _removeExcludedParameters();
      });
    } else if (ApplicationProfileManager.isWindows()) {
      deviceInfo.windowsInfo.then((windowsInfo) {
        _loadWindowsParameters(windowsInfo);
        _removeExcludedParameters();
      });
    } else if (ApplicationProfileManager.isMacOS()) {
      deviceInfo.macOsInfo.then((macOsDeviceInfo) {
        _loadMacOSParameters(macOsDeviceInfo);
        _removeExcludedParameters();
      });
    } else if (ApplicationProfileManager.isAndroid()) {
      deviceInfo.androidInfo.then((androidInfo) {
        _loadAndroidParameters(androidInfo);
        _removeExcludedParameters();
      });
    } else if (ApplicationProfileManager.isIos()) {
      deviceInfo.iosInfo.then((iosInfo) {
        _loadIosParameters(iosInfo);
        _removeExcludedParameters();
      });
    } else {
      _logger.info("Couldn't load device info for unsupported device type.");
    }
  }

  ///Remove excluded parameters from device parameters.
  void _removeExcludedParameters() {
    for (var parameter in _currentConfig.excludedParameters) {
      _deviceParameters.remove(parameter);
    }
  }

  void _loadLinuxParameters(LinuxDeviceInfo linuxDeviceInfo) {
    try {
      _deviceParameters["name"] = linuxDeviceInfo.name;
      _deviceParameters["version"] = linuxDeviceInfo.version;
      _deviceParameters["id"] = linuxDeviceInfo.id;
      _deviceParameters["idLike"] = linuxDeviceInfo.idLike;
      _deviceParameters["versionCodename"] = linuxDeviceInfo.versionCodename;
      _deviceParameters["versionId"] = linuxDeviceInfo.versionId;
      _deviceParameters["prettyName"] = linuxDeviceInfo.prettyName;
      _deviceParameters["buildId"] = linuxDeviceInfo.buildId;
      _deviceParameters["variant"] = linuxDeviceInfo.variant;
      _deviceParameters["variantId"] = linuxDeviceInfo.variantId;
      _deviceParameters["machineId"] = linuxDeviceInfo.machineId;
    } catch (exception) {
      _logger.warning("Load Linux parameters failed: $exception");
    }
  }

  void _loadMacOSParameters(MacOsDeviceInfo macOsDeviceInfo) {
    try {
      _deviceParameters["computerName"] = macOsDeviceInfo.computerName;
      _deviceParameters["hostName"] = macOsDeviceInfo.hostName;
      _deviceParameters["arch"] = macOsDeviceInfo.arch;
      _deviceParameters["model"] = macOsDeviceInfo.model;
      _deviceParameters["kernelVersion"] = macOsDeviceInfo.kernelVersion;
      _deviceParameters["osRelease"] = macOsDeviceInfo.osRelease;
      _deviceParameters["activeCPUs"] = macOsDeviceInfo.activeCPUs;
      _deviceParameters["memorySize"] = macOsDeviceInfo.memorySize;
      _deviceParameters["cpuFrequency"] = macOsDeviceInfo.cpuFrequency;
    } catch (exception) {
      _logger.warning("Load MacOS parameters failed: $exception");
    }
  }

  void _loadWindowsParameters(WindowsDeviceInfo windowsDeviceInfo) {
    try {
      _deviceParameters["computerName"] = windowsDeviceInfo.computerName;
      _deviceParameters["numberOfCores"] = windowsDeviceInfo.numberOfCores;
      _deviceParameters["systemMemoryInMegabytes"] = windowsDeviceInfo.systemMemoryInMegabytes;
    } catch (exception) {
      _logger.warning("Load Windows parameters failed: $exception");
    }
  }

  void _loadWebParameters(WebBrowserInfo webBrowserInfo) async {
    try {
      _deviceParameters["language"] = webBrowserInfo.language;
      _deviceParameters["appCodeName"] = webBrowserInfo.appCodeName;
      _deviceParameters["appName"] = webBrowserInfo.appName;
      _deviceParameters["appVersion"] = webBrowserInfo.appVersion;
      _deviceParameters["browserName"] = webBrowserInfo.browserName.toString();
      _deviceParameters["deviceMemory"] = webBrowserInfo.deviceMemory;
      _deviceParameters["hardwareConcurrency"] = webBrowserInfo.hardwareConcurrency;
      _deviceParameters["languages"] = webBrowserInfo.languages;
      _deviceParameters["maxTouchPoints"] = webBrowserInfo.maxTouchPoints;
      _deviceParameters["platform"] = webBrowserInfo.platform;
      _deviceParameters["product"] = webBrowserInfo.product;
      _deviceParameters["productSub"] = webBrowserInfo.productSub;
      _deviceParameters["userAgent"] = webBrowserInfo.userAgent;
      _deviceParameters["vendor"] = webBrowserInfo.vendor;
      _deviceParameters["vendorSub"] = webBrowserInfo.vendorSub;
    } catch (exception) {
      _logger.warning("Load Web parameters failed: $exception");
    }
  }

  void _loadAndroidParameters(AndroidDeviceInfo androidDeviceInfo) {
    try {
      _deviceParameters["id"] = androidDeviceInfo.id;
      _deviceParameters["androidId"] = androidDeviceInfo.androidId;
      _deviceParameters["board"] = androidDeviceInfo.board;
      _deviceParameters["bootloader"] = androidDeviceInfo.bootloader;
      _deviceParameters["brand"] = androidDeviceInfo.brand;
      _deviceParameters["device"] = androidDeviceInfo.device;
      _deviceParameters["display"] = androidDeviceInfo.display;
      _deviceParameters["fingerprint"] = androidDeviceInfo.fingerprint;
      _deviceParameters["hardware"] = androidDeviceInfo.hardware;
      _deviceParameters["host"] = androidDeviceInfo.host;
      _deviceParameters["isPhysicalDevice"] = androidDeviceInfo.isPhysicalDevice;
      _deviceParameters["manufacturer"] = androidDeviceInfo.manufacturer;
      _deviceParameters["model"] = androidDeviceInfo.model;
      _deviceParameters["product"] = androidDeviceInfo.product;
      _deviceParameters["tags"] = androidDeviceInfo.tags;
      _deviceParameters["type"] = androidDeviceInfo.type;
      _deviceParameters["versionBaseOs"] = androidDeviceInfo.version.baseOS;
      _deviceParameters["versionCodename"] = androidDeviceInfo.version.codename;
      _deviceParameters["versionIncremental"] = androidDeviceInfo.version.incremental;
      _deviceParameters["versionPreviewSdk"] = androidDeviceInfo.version.previewSdkInt;
      _deviceParameters["versionRelease"] = androidDeviceInfo.version.release;
      _deviceParameters["versionSdk"] = androidDeviceInfo.version.sdkInt;
      _deviceParameters["versionSecurityPatch"] = androidDeviceInfo.version.securityPatch;
    } catch (exception) {
      _logger.warning("Load Android parameters failed: $exception");
    }
  }

  void _loadIosParameters(IosDeviceInfo iosInfo) {
    try {
      _deviceParameters["model"] = iosInfo.model;
      _deviceParameters["isPhysicalDevice"] = iosInfo.isPhysicalDevice;
      _deviceParameters["name"] = iosInfo.name;
      _deviceParameters["identifierForVendor"] = iosInfo.identifierForVendor;
      _deviceParameters["localizedModel"] = iosInfo.localizedModel;
      _deviceParameters["systemName"] = iosInfo.systemName;
      _deviceParameters["utsnameVersion"] = iosInfo.utsname.version;
      _deviceParameters["utsnameRelease"] = iosInfo.utsname.release;
      _deviceParameters["utsnameMachine"] = iosInfo.utsname.machine;
      _deviceParameters["utsnameNodename"] = iosInfo.utsname.nodename;
      _deviceParameters["utsnameSysname"] = iosInfo.utsname.sysname;
    } catch (exception) {
      _logger.warning("Load iOS parameters failed: $exception");
    }
  }

  void _loadApplicationInfo() {
    _applicationParameters["environment"] = describeEnum(ApplicationProfileManager.getApplicationProfile());

    PackageInfo.fromPlatform().then((packageInfo) {
      _applicationParameters["version"] = packageInfo.version;
      _applicationParameters["appName"] = packageInfo.appName;
      _applicationParameters["buildNumber"] = packageInfo.buildNumber;
      _applicationParameters["packageName"] = packageInfo.packageName;
    });
  }

  ///We need to setup localizations lazily because context needed to setup these
  ///localizations can be used after app was build for the first time.
  void _setupLocalization() {
    Locale locale = const Locale("en", "US");
    if (_isContextValid()) {
      final BuildContext? context = _getContext();
      if (context != null) {
        locale = Localizations.localeOf(context);
      }
      if (_currentConfig.localizationOptions.isNotEmpty == true) {
        for (final options in _currentConfig.localizationOptions) {
          if (options.languageCode.toLowerCase() == locale.languageCode.toLowerCase()) {
            _localizationOptions = options;
          }
        }
      }
    }

    _localizationOptions ??= _getDefaultLocalizationOptionsForLanguage(locale.languageCode);
    _setupLocalizationsOptionsInReportMode();
    _setupLocalizationsOptionsInReportsHandler();
  }

  LocalizationOptions _getDefaultLocalizationOptionsForLanguage(
    String language,
  ) {
    switch (language.toLowerCase()) {
      case "en":
        return LocalizationOptions.buildDefaultEnglishOptions();
      case "zh":
        return LocalizationOptions.buildDefaultChineseOptions();
      case "hi":
        return LocalizationOptions.buildDefaultHindiOptions();
      case "es":
        return LocalizationOptions.buildDefaultSpanishOptions();
      case "ms":
        return LocalizationOptions.buildDefaultMalayOptions();
      case "ru":
        return LocalizationOptions.buildDefaultRussianOptions();
      case "pt":
        return LocalizationOptions.buildDefaultPortugueseOptions();
      case "fr":
        return LocalizationOptions.buildDefaultFrenchOptions();
      case "pl":
        return LocalizationOptions.buildDefaultPolishOptions();
      case "it":
        return LocalizationOptions.buildDefaultItalianOptions();
      case "ko":
        return LocalizationOptions.buildDefaultKoreanOptions();
      case "nl":
        return LocalizationOptions.buildDefaultDutchOptions();
      case "de":
        return LocalizationOptions.buildDefaultGermanOptions();
      default:
        return LocalizationOptions.buildDefaultEnglishOptions();
    }
  }

  /// Report checked error (error caught in try-catch block). Catcher will treat
  /// this as normal exception and pass it to handlers.
  static void reportCheckedError(dynamic error, dynamic stackTrace, String methodName) {
    dynamic errorValue = error;
    dynamic stackTraceValue = stackTrace;
    errorValue ??= "undefined error";
    stackTraceValue ??= StackTrace.current;

    _instance._reportError(error, stackTrace);
  }

  void _reportError(
    dynamic error,
    dynamic stackTrace, {
    FlutterErrorDetails? errorDetails,
    String? methodName,
  }) async {
    if (errorDetails?.silent == true && _currentConfig.handleSilentError == false) {
      _logger.info(
        "Report error skipped for error: $error. HandleSilentError is false.",
      );
      return;
    }

    if (_localizationOptions == null) {
      _logger.info("Setup localization lazily!");
      _setupLocalization();
    }

    _cleanPastReportsOccurences();

    if (methodName != null) {
      _currentConfig.customParameters.addAll({
        "methodName": methodName,
      });
    }

    final Report report = Report(
      error,
      stackTrace,
      DateTime.now(),
      _deviceParameters,
      _applicationParameters,
      _currentConfig.customParameters,
      errorDetails,
      _getPlatformType(),
    );

    if (_isReportInReportsOccurencesMap(report)) {
      _logger.fine(
        "Error: '$error' has been skipped to due to duplication occurence within ${_currentConfig.reportOccurrenceTimeout} ms.",
      );
      return;
    }

    if (_currentConfig.filterFunction != null && _currentConfig.filterFunction!(report) == false) {
      _logger.fine(
        "Error: '$error' has been filtered from Catcher logs. Report will be skipped.",
      );
      return;
    }
    _cachedReports.add(report);
    ReportMode? reportMode = _getReportModeFromExplicitExceptionReportModeMap(error);
    if (reportMode != null) {
      _logger.info("Using explicit report mode for error");
    } else {
      reportMode = _currentConfig.reportMode;
    }
    if (!isReportModeSupportedInPlatform(report, reportMode)) {
      _logger.warning(
        "$reportMode in not supported for ${describeEnum(report.platformType)} platform",
      );
      return;
    }

    _addReportInReportsOccurencesMap(report);

    if (reportMode.isContextRequired()) {
      if (_isContextValid()) {
        reportMode.requestAction(report, _getContext());
      } else {
        _logger.warning(
          "Couldn't use report mode because you didn't provide navigator key. Add navigator key to use this report mode.",
        );
      }
    } else {
      reportMode.requestAction(report, null);
    }
  }

  /// Check if given report mode is enabled in current platform. Only supported
  /// handlers in given report mode can be used.
  bool isReportModeSupportedInPlatform(Report report, ReportMode reportMode) {
    if (reportMode.getSupportedPlatforms().isEmpty) {
      return false;
    }
    return reportMode.getSupportedPlatforms().contains(report.platformType);
  }

  ReportMode? _getReportModeFromExplicitExceptionReportModeMap(dynamic error) {
    final errorName = error != null ? error.toString().toLowerCase() : "";
    ReportMode? reportMode;
    _currentConfig.explicitExceptionReportModesMap.forEach((key, value) {
      if (errorName.contains(key.toLowerCase())) {
        reportMode = value;
        return;
      }
    });
    return reportMode;
  }

  ReportHandler? _getReportHandlerFromExplicitExceptionHandlerMap(
    dynamic error,
  ) {
    final errorName = error != null ? error.toString().toLowerCase() : "";
    ReportHandler? reportHandler;
    _currentConfig.explicitExceptionHandlersMap.forEach((key, value) {
      if (errorName.contains(key.toLowerCase())) {
        reportHandler = value;
        return;
      }
    });
    return reportHandler;
  }

  @override
  void onActionConfirmed(Report report) {
    final ReportHandler? reportHandler = _getReportHandlerFromExplicitExceptionHandlerMap(report.error);
    if (reportHandler != null) {
      _logger.info("Using explicit report handler");
      _handleReport(report, reportHandler);
      return;
    }

    for (final ReportHandler handler in _currentConfig.handlers) {
      _handleReport(report, handler);
    }
  }

  void _handleReport(Report report, ReportHandler reportHandler) {
    if (!isReportHandlerSupportedInPlatform(report, reportHandler)) {
      _logger.warning(
        "$reportHandler in not supported for ${describeEnum(report.platformType)} platform",
      );
      return;
    }

    if (reportHandler.isContextRequired() && !_isContextValid()) {
      _logger.warning(
        "Couldn't use report handler because you didn't provide navigator key. Add navigator key to use this report mode.",
      );
      return;
    }

    reportHandler.handle(report, _getContext()).catchError((dynamic handlerError) {
      _logger.warning(
        "Error occurred in ${reportHandler.toString()}: ${handlerError.toString()}",
      );
    }).then((result) {
      _logger.info("${report.runtimeType} result: $result");
      if (!result) {
        _logger.warning("${reportHandler.toString()} failed to report error");
      } else {
        _cachedReports.remove(report);
      }
    }).timeout(
      Duration(milliseconds: _currentConfig.handlerTimeout),
      onTimeout: () {
        _logger.warning(
          "${reportHandler.toString()} failed to report error because of timeout",
        );
      },
    );
  }

  /// Checks is report handler is supported in given platform. Only supported
  /// report handlers in given platform can be used.
  bool isReportHandlerSupportedInPlatform(
    Report report,
    ReportHandler reportHandler,
  ) {
    if (reportHandler.getSupportedPlatforms().isEmpty == true) {
      return false;
    }
    return reportHandler.getSupportedPlatforms().contains(report.platformType);
  }

  @override
  void onActionRejected(Report report) {
    _currentConfig.handlers.where((handler) => handler.shouldHandleWhenRejected()).forEach((handler) {
      _handleReport(report, handler);
    });

    _cachedReports.remove(report);
  }

  BuildContext? _getContext() {
    return navigatorKey?.currentState?.overlay?.context;
  }

  bool _isContextValid() {
    return navigatorKey?.currentState?.overlay != null;
  }

  /// Get currently used config.
  CatcherOptions? getCurrentConfig() {
    return _currentConfig;
  }

  /// Send text exception. Used to test Catcher configuration.
  static void sendTestException() {
    throw const FormatException("Test exception generated by Catcher");
  }

  /// Add default error widget which replaces red screen of death (RSOD).
  static void addDefaultErrorWidget({
    bool showStacktrace = true,
    String title = "An application error has occurred",
    String description = "There was unexpected situation in application. Application has been "
        "able to recover from error state.",
    double maxWidthForSmallMode = 150,
  }) {
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return CatcherErrorWidget(
        details: details,
        showStacktrace: showStacktrace,
        title: title,
        description: description,
        maxWidthForSmallMode: maxWidthForSmallMode,
      );
    };
  }

  ///Get platform type based on device.
  PlatformType _getPlatformType() {
    if (ApplicationProfileManager.isWeb()) {
      return PlatformType.web;
    }
    if (ApplicationProfileManager.isAndroid()) {
      return PlatformType.android;
    }
    if (ApplicationProfileManager.isIos()) {
      return PlatformType.iOS;
    }
    if (ApplicationProfileManager.isLinux()) {
      return PlatformType.linux;
    }
    if (ApplicationProfileManager.isWindows()) {
      return PlatformType.windows;
    }
    if (ApplicationProfileManager.isMacOS()) {
      return PlatformType.macOS;
    }

    return PlatformType.unknown;
  }

  ///Clean report ocucrences from the past.
  void _cleanPastReportsOccurences() {
    final occurenceTimeout = _currentConfig.reportOccurrenceTimeout;
    final nowDateTime = DateTime.now();
    _reportsOcurrenceMap.removeWhere((key, value) {
      final occurenceWithTimeout = key.add(Duration(milliseconds: occurenceTimeout));
      return nowDateTime.isAfter(occurenceWithTimeout);
    });
  }

  ///Check whether reports occurence map contains given report.
  bool _isReportInReportsOccurencesMap(Report report) {
    if (report.error != null) {
      return _reportsOcurrenceMap.containsValue(report.error.toString());
    } else {
      return false;
    }
  }

  ///Add report in reports occurences map. Report will be added only when
  ///error is not null and report occurence timeout is greater than 0.
  void _addReportInReportsOccurencesMap(Report report) {
    if (report.error != null && _currentConfig.reportOccurrenceTimeout > 0) {
      _reportsOcurrenceMap[DateTime.now()] = report.error.toString();
    }
  }

  ///Get current Catcher instance.
  static AthmanyCatcher getInstance() {
    return _instance;
  }

  void _sendCachedReports() async {
    final cache = GetStorage();
    final cahcedRequests = cache.read<String?>('cachedRequests');
    if (cahcedRequests != null) {
      final requests = cachedRequestFromJson(cahcedRequests);
      for (final request in requests) {
        final result = await _sendReport(request);
        if (result) {
          requests.remove(request);
        }
      }
      if (requests.isNotEmpty) {
        cache.write('cachedRequests', cachedRequestToJson(requests));
      }
    }
  }

  Future<bool> _sendReport(CachedRequest request) async {
    final response = await dio.post(request.url, data: request.body.toJson());
    return response.statusCode == 200;
  }
}
