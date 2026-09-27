import 'package:flutter/material.dart';

/// 日志心情 / 天气图标映射（用图标替代表情，浅色下更统一耐看）
const moodIcons = <String, IconData>{
  '平静': Icons.spa_outlined,
  '开心': Icons.sentiment_satisfied_alt,
  '兴奋': Icons.celebration_outlined,
  '难过': Icons.sentiment_very_dissatisfied,
  '疲惫': Icons.bedtime_outlined,
};

const weatherIcons = <String, IconData>{
  '晴': Icons.wb_sunny_outlined,
  '多云': Icons.wb_cloudy_outlined,
  '阴': Icons.cloud_outlined,
  '雨': Icons.water_drop_outlined,
  '雪': Icons.ac_unit,
};

/// 供编辑页展示"心情"选项
const moodOptions = ['平静', '开心', '兴奋', '难过', '疲惫'];

/// 供编辑页展示"天气"选项
const weatherOptions = ['晴', '多云', '阴', '雨', '雪'];