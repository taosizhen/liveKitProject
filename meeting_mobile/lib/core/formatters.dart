import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// 时间格式化：今天 / 明天 / 具体日期
String formatMeetingTime(DateTime time) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(time.year, time.month, time.day);
  final diffDays = target.difference(today).inDays;
  final hm = DateFormat('HH:mm').format(time);
  if (diffDays == 0) return '今天 $hm';
  if (diffDays == 1) return '明天 $hm';
  if (diffDays == -1) return '昨天 $hm';
  return DateFormat('MM月dd日 HH:mm').format(time);
}

/// 消息时间：HH:mm
String formatMessageTime(DateTime time) => DateFormat('HH:mm').format(time);

/// 会议状态对应颜色
Color statusColor(String status) {
  switch (status) {
    case 'in_progress':
      return const Color(0xFF10B981);
    case 'scheduled':
      return const Color(0xFF6366F1);
    case 'cancelled':
      return const Color(0xFFEF4444);
    case 'completed':
      return const Color(0xFF94A3B8);
    default:
      return const Color(0xFF94A3B8);
  }
}

/// 会议状态标签背景色（浅色底）
Color statusBackground(String status) => statusColor(status).withOpacity(0.12);
