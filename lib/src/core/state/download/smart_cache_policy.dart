import '../../models/models.dart';

class SmartCachePolicy {
  const SmartCachePolicy(
      {this.enabled = false,
      this.wifiOnly = true,
      this.ahead = 5,
      this.deletePlayed = true,
      this.maxMegabytes = 1024});
  final bool enabled;
  final bool wifiOnly;
  final int ahead;
  final bool deletePlayed;
  final int maxMegabytes;
  int get maxBytes => maxMegabytes * 1024 * 1024;

  factory SmartCachePolicy.fromJson(Map<String, dynamic> json) =>
      SmartCachePolicy(
        enabled: json['enabled'] == true,
        wifiOnly: json['wifi_only'] != false,
        ahead: ((json['ahead'] as num?)?.toInt() ?? 5).clamp(1, 50),
        deletePlayed: json['delete_played'] != false,
        maxMegabytes: ((json['max_megabytes'] as num?)?.toInt() ?? 1024)
            .clamp(100, 10240),
      );
  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'wifi_only': wifiOnly,
        'ahead': ahead,
        'delete_played': deletePlayed,
        'max_megabytes': maxMegabytes
      };

  List<Chapter> window(List<Chapter> chapters, String currentId) {
    final index = chapters.indexWhere((item) => item.id == currentId);
    if (index < 0) return [];
    return chapters.skip(index).take(ahead + 1).toList();
  }
}
