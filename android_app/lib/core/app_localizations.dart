import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../security/keystore_service.dart';

enum AppLang { fa, en }

class AppLocaleNotifier extends StateNotifier<AppLang> {
  final KeystoreService _keystore = KeystoreService();

  AppLocaleNotifier() : super(_detectDeviceDefault()) {
    _loadSaved();
  }

  static AppLang _detectDeviceDefault() {
    try {
      final code = ui.PlatformDispatcher.instance.locale.languageCode.toLowerCase();
      if (code == 'fa' || code == 'ar') {
        return AppLang.fa;
      }
      return AppLang.fa; // Default to Persian with 1-tap toggle to English
    } catch (_) {
      return AppLang.fa;
    }
  }

  Future<void> _loadSaved() async {
    try {
      final saved = await _keystore.getLanguageCode();
      if (saved == 'en') {
        state = AppLang.en;
      } else if (saved == 'fa') {
        state = AppLang.fa;
      } else {
        final code = ui.PlatformDispatcher.instance.locale.languageCode.toLowerCase();
        state = (code == 'en') ? AppLang.en : AppLang.fa;
      }
    } catch (_) {}
  }

  void toggleLanguage() {
    final next = state == AppLang.fa ? AppLang.en : AppLang.fa;
    state = next;
    _keystore.saveLanguageCode(next.name);
  }

  void setLanguage(AppLang lang) {
    state = lang;
    _keystore.saveLanguageCode(lang.name);
  }
}

final appLocaleProvider = StateNotifierProvider<AppLocaleNotifier, AppLang>((ref) {
  return AppLocaleNotifier();
});

class S {
  final AppLang lang;
  const S(this.lang);

  bool get isFa => lang == AppLang.fa;
  TextDirection get dir => isFa ? TextDirection.rtl : TextDirection.ltr;

  String tr(String fa, String en) => isFa ? fa : en;
}
