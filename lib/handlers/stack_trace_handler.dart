import 'package:flutter/foundation.dart';
import 'package:stack_trace/stack_trace.dart';

class CustomTrace {
  late final StackTrace stack;

  String? fileName;
  String? functionName;
  String? callerFunctionName;
  int? lineNumber;
  int? columnNumber;

  CustomTrace(this.stack) {
    _parseTrace();
  }

  String _getFunctionNameFromFrame(String frame) {
    var currentTrace = frame;

    var indexOfWhiteSpace = currentTrace.indexOf(' ');

    var subStr = currentTrace.substring(indexOfWhiteSpace);

    final indexOfFunction = subStr.indexOf(RegExp(r'[A-Za-z0-9]'));

    subStr = subStr.substring(indexOfFunction);

    indexOfWhiteSpace = subStr.indexOf(' ');

    subStr = subStr.substring(0, indexOfWhiteSpace);

    return subStr;
  }

  void _parseTrace() {
    var frames = stack.toString().split("\n");

    functionName = _getFunctionNameFromFrame(frames[0]);

    callerFunctionName = _getFunctionNameFromFrame(frames[1]);

    var traceString = frames[0];

    var indexOfFileName = traceString.indexOf(RegExp(r'[A-Za-z]+.dart'));

    var fileInfo = traceString.substring(indexOfFileName);

    var listOfInfos = fileInfo.split(":");

    fileName = listOfInfos[0];
    lineNumber = int.parse(listOfInfos[1]);
    var columnStr = listOfInfos[2];
    columnStr = columnStr.replaceFirst(")", "");
    columnNumber = int.parse(columnStr);
  }

  printError(error, {bool simple = true}) {
    debugLog(error.toString(), isShowTime: false, showLine: true, isDescription: true);
    String errorStr = "";
    if (simple) {
      errorStr = _parseFlutterStack(Trace.from(stack));
    } else {
      errorStr = Trace.from(stack).toString();
    }
    if (errorStr.isNotEmpty) {
      debugLog(errorStr, isShowTime: false, showLine: true, isDescription: false);
    }
  }

  String _parseFlutterStack(Trace trace) {
    String result = "";
    String traceStr = trace.toString();
    List<String> strs = traceStr.split("\n");
    for (var str in strs) {
      if (!str.contains("package:flutter/") && !str.contains("dart:") && !str.contains("package:flutter_stack_trace/")) {
        if (str.isNotEmpty) {
          if (result.isNotEmpty) {
            result = "$result\n$str";
          } else {
            result = str;
          }
        }
      }
    }
    return result;
  }

  void debugLog(Object obj, {bool isShowTime = false, bool showLine = true, int maxLength = 100, bool isDescription = true}) {
    bool isDebug = false;
    assert(isDebug = true);

    if (isDebug) {
      String slice = obj.toString();
      if (isDescription) {
        if (obj.toString().length > maxLength) {
          List<String> objSlice = [];
          for (int i = 0; i < (obj.toString().length % maxLength == 0 ? obj.toString().length / maxLength : obj.toString().length / maxLength + 1); i++) {
            if (maxLength * i > obj.toString().length) {
              break;
            }
            objSlice.add(obj.toString().substring(maxLength * i, maxLength * (i + 1) > obj.toString().length ? obj.toString().length : maxLength * (i + 1)));
          }
          slice = "\n";
          for (var element in objSlice) {
            slice += "$element\n";
          }
        }
      }
      _print(slice, showLine: showLine, isShowTime: isShowTime);
    }
  }

  _print(String content, {bool isShowTime = true, bool showLine = false}) {
    String log = isShowTime ? "${DateTime.now()}:  $content" : content;
    if (showLine) {
      var logSlice = log.split("\n");
      int maxLength = _getMaxLength(logSlice) + 3;
      String line = "-";
      for (int i = 0; i < maxLength + 1; i++) {
        line = "$line-";
      }
      debugPrint(line);
      for (var log in logSlice) {
        if (log.isEmpty) {
          continue;
        }
        int gapLength = maxLength - log.length;
        if (gapLength > 0) {
          String space = " ";
          for (int i = 0; i < gapLength - 3; i++) {
            space = "$space ";
          }
          debugPrint("| $log$space |");
        }
      }
      debugPrint(line);
    } else {
      debugPrint(log);
    }
  }

  int _getMaxLength(List<String> logSlice) {
    List<int> lengthList = <int>[];
    for (var log in logSlice) {
      lengthList.add(log.length);
    }
    lengthList.sort((left, right) => right - left);
    return lengthList[0];
  }

  @override
  String toString() =>
      ("Source file: $fileName, function: $functionName, caller function: $callerFunctionName, current line of code since the instanciation/creation of the custom trace object: $lineNumber, even the column(yay!): $columnNumber");
}
