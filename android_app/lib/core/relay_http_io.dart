import 'dart:convert';
import 'dart:io';

Future<String?> relayHttpGet(String url) async {
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return await res.transform(utf8.decoder).join();
    }
  } catch (_) {}
  return null;
}

Future<String?> relayHttpPost(String url, Map<String, dynamic> body) async {
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    final req = await client.postUrl(Uri.parse(url));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final res = await req.close();
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return await res.transform(utf8.decoder).join();
    }
  } catch (_) {}
  return null;
}
