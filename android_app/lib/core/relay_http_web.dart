import 'dart:convert';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

Future<String?> relayHttpGet(String url) async {
  try {
    final resp = await web.window.fetch(url.toJS).toDart;
    if (resp.ok) {
      final txt = await resp.text().toDart;
      return txt.toDart;
    }
  } catch (_) {}
  return null;
}

Future<String?> relayHttpPost(String url, Map<String, dynamic> body) async {
  try {
    final headers = web.Headers();
    headers.append('Content-Type', 'application/json');
    final init = web.RequestInit(
      method: 'POST',
      headers: headers,
      body: jsonEncode(body).toJS,
    );
    final resp = await web.window.fetch(url.toJS, init).toDart;
    if (resp.ok) {
      final txt = await resp.text().toDart;
      return txt.toDart;
    }
  } catch (_) {}
  return null;
}

void openExternalUrlInBrowser(String url) {
  try {
    web.window.open(url, '_blank');
  } catch (_) {}
}
