import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static String get supabaseUrl =>
      dotenv.get('SUPABASE_URL', fallback: 'https://fzmtnzcjxsrdohaesfsz.supabase.co');
  static String get supabaseAnonKey =>
      dotenv.get('SUPABASE_ANON_KEY', fallback: '');

  static String get apiBaseUrl {
    if (kIsWeb) {
      return dotenv.get('API_BASE_URL_WEB', fallback: 'http://localhost:8000/api/v1');
    }
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return dotenv.get('API_BASE_URL_DESKTOP', fallback: 'http://127.0.0.1:8000/api/v1');
    }
    return dotenv.get('API_BASE_URL', fallback: 'http://192.168.0.104:8000/api/v1');
  }
}
