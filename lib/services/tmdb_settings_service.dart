import 'package:shared_preferences/shared_preferences.dart';
import 'tmdb_service.dart';

/// TMDB 设置持久化服务
class TMDBSettingsService {
  static const _key = 'tmdb_api_key';

  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  static Future<void> setApiKey(String? key) async {
    final prefs = await SharedPreferences.getInstance();
    if (key == null || key.isEmpty) {
      await prefs.remove(_key);
      TMDBService.instance.setApiKey('');
    } else {
      await prefs.setString(_key, key);
      TMDBService.instance.setApiKey(key);
    }
  }

  static Future<void> init() async {
    final key = await getApiKey();
    if (key != null && key.isNotEmpty) {
      TMDBService.instance.setApiKey(key);
    }
  }
}
