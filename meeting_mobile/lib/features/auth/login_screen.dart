import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_controller.dart';

/// 登录页
///
/// 调用后端 `POST /auth/login`，成功后 refresh_token 写入 secure_storage。
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// 提交登录
  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final ok = await ref
        .read(authControllerProvider.notifier)
        .login(_emailController.text, _passwordController.text);
    if (!mounted) return;
    if (ok) {
      context.go('/meetings');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 72),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.video_camera_front_rounded,
                      size: 34, color: Color(0xFF4F46E5)),
                ),
                const SizedBox(height: 24),
                const Text(
                  '欢迎回来',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  '登录后查看会议安排并加入会议',
                  style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: '邮箱',
                    hintText: 'name@example.com',
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return '请输入邮箱';
                    if (!text.contains('@')) return '邮箱格式不正确';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: '密码',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (value) =>
                      (value == null || value.isEmpty) ? '请输入密码' : null,
                ),
                if (auth.error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            size: 16, color: Color(0xFFDC2626)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            auth.error!,
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFFB91C1C)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: auth.busy ? null : _submit,
                    child: auth.busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('登录', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '账号由管理员在 PC 端创建，如忘记密码请联系管理员',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
