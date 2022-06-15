import 'dart:convert';

List<CachedRequest> cachedRequestFromJson(String str) => List<CachedRequest>.from(json.decode(str).map((x) => CachedRequest.fromJson(x)));

String cachedRequestToJson(List<CachedRequest> data) => json.encode(List<dynamic>.from(data.map((x) => x.toJson())));

class CachedRequest {
  CachedRequest({
    required this.url,
    required this.body,
  });

  final String url;
  final Body body;

  factory CachedRequest.fromJson(Map<String, dynamic> json) => CachedRequest(
        url: json["url"],
        body: Body.fromJson(json["body"]),
      );

  Map<String, dynamic> toJson() => {
        "url": url,
        "body": body.toJson(),
      };
}

class Body {
  Body({
    required this.method,
    required this.posProfile,
    required this.dateTime,
    required this.error,
  });

  final String method;
  final String posProfile;
  final String dateTime;
  final String error;

  factory Body.fromJson(Map<String, dynamic> json) => Body(
        method: json["method"],
        posProfile: json["pos_profile"],
        dateTime: json["date_time"],
        error: json["error"],
      );

  Map<String, dynamic> toJson() => {
        "method": method,
        "pos_profile": posProfile,
        "date_time": dateTime,
        "error": error,
      };
}
