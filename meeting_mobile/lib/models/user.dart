/// 当前登录用户
///
/// 对应后端 `/auth/login`、`/auth/me` 返回的 `user` 结构：
/// `{ id, email, name, role }`
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.avatarUrl,
  });

  final String id;
  final String email;
  final String name;

  /// 角色标识：admin / teacher / student（后端 role_name）
  final String role;

  /// 头像地址；Demo 数据可能为空，UI 层需做首字母兜底
  final String? avatarUrl;

  /// 角色中文名
  String get roleLabel {
    switch (role) {
      case 'admin':
        return '管理员';
      case 'teacher':
        return '教师';
      case 'student':
        return '学生';
      default:
        return role;
    }
  }

  /// 展示名（为空时退回邮箱前缀）
  String get displayName => name.isNotEmpty ? name : email.split('@').first;

  /// 头像占位文案：取名字首字（中文逐字安全，BMP 字符直接截取）
  String get initial =>
      displayName.isEmpty ? '?' : displayName.substring(0, 1);

  /// 解析用户 JSON；兼容 role 为字符串或对象两种返回
  factory AppUser.fromJson(Map<String, dynamic> json) {
    final rawRole = json['role'];
    String role;
    if (rawRole is String) {
      role = rawRole;
    } else if (rawRole is Map<String, dynamic>) {
      role = (rawRole['name'] as String?) ?? '';
    } else {
      role = (json['role_name'] as String?) ?? '';
    }
    return AppUser(
      id: (json['id'] ?? '').toString(),
      email: (json['email'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      role: role,
      avatarUrl: (json['avatar_url'] as String?)?.isEmpty == true
          ? null
          : json['avatar_url'] as String?,
    );
  }

  /// 序列化为本地缓存
  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'role': role,
        'avatar_url': avatarUrl,
      };
}
