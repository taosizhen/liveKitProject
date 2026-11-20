import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../models/token_pair.dart';
import 'token_storage.dart';

/// 业务异常（后端 code != 0 或网络错误）
class ApiException implements Exception {
  ApiException(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() => message;
}

/// 统一 HTTP 客户端
///
/// 关键职责：
/// 1. 自动附加 `Authorization: Bearer <access_token>`
/// 2. 401 时用 refresh_token 换新 token 并重放原请求
/// 3. **单例刷新队列**：并发 401 只触发一次 /auth/refresh，其余请求等待同一 Future
/// 4. refresh 失败 → 清空登录态并回调 `onAuthLost`（路由跳登录页）
class ApiClient {
  ApiClient({required AppConfig config, required TokenStorage tokens})
      : _config = config,
        _tokens = tokens,
        _dio = Dio(BaseOptions(
          baseUrl: config.apiBase,
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 20),
          contentType: Headers.jsonContentType,
        )),
        _refreshDio = Dio(BaseOptions(
          baseUrl: config.apiBase,
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 20),
          contentType: Headers.jsonContentType,
        )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onError: _onError,
    ));

    // 由 assets/config.json 的 allow_bad_certificate 控制：
    // 本地联调为 true（后端使用 mkcert 自签证书），对外生产打包时应改为 false
    if (_config.allowBadCertificate) {
      _dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient()
            ..badCertificateCallback = (cert, host, port) => true;
          return client;
        },
      );
      _refreshDio.httpClientAdapter = _dio.httpClientAdapter;
    }
  }

  final AppConfig _config;
  final TokenStorage _tokens;
  final Dio _dio;

  /// 专门用于刷新 token 的 Dio，不挂拦截器，避免递归
  final Dio _refreshDio;

  /// 登录态丢失回调，由 app 层注入（跳转登录页）
  void Function()? onAuthLost;

  /// 正在进行的刷新任务（并发请求共享）
  Future<TokenPair>? _refreshInFlight;

  /// 是否已提示过登录失效，避免并发 401 重复跳转
  bool _authLostNotified = false;

  /// 请求拦截：自动加 Bearer Token
  void _onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _tokens.accessToken;
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  /// 错误拦截：401 自动刷新并重放
  Future<void> _onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final request = err.requestOptions;
    final isAuthPath = request.path.contains('/auth/login') ||
        request.path.contains('/auth/refresh');
    final alreadyRetried = request.extra['retried'] == true;

    if (err.response?.statusCode != 401 || isAuthPath || alreadyRetried) {
      handler.next(err);
      return;
    }

    final refreshToken = await _tokens.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await _notifyAuthLost();
      handler.next(err);
      return;
    }

    try {
      final pair = await _ensureRefreshed();
      request.extra['retried'] = true;
      request.headers['Authorization'] = 'Bearer ${pair.accessToken}';
      final response = await _dio.fetch(request);
      handler.resolve(response);
    } catch (_) {
      await _notifyAuthLost();
      handler.next(err);
    }
  }

  /// 共享刷新：并发 401 只发起一次 /auth/refresh
  Future<TokenPair> _ensureRefreshed() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    final future = _performRefresh();
    _refreshInFlight = future;
    future.whenComplete(() {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    });
    return future;
  }

  /// 真正执行刷新（供拦截器与启动页复用）
  Future<TokenPair> refresh() => _ensureRefreshed();

  /// 调用 /auth/refresh 换取新 token 并落盘
  Future<TokenPair> _performRefresh() async {
    final refreshToken = await _tokens.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      throw ApiException('登录已过期，请重新登录', code: 401);
    }
    try {
      final response = await _refreshDio.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final body = response.data;
      if (body is! Map<String, dynamic> || body['code'] != 0) {
        throw ApiException(
          (body is Map<String, dynamic> ? body['message'] as String? : null) ??
              '登录已过期，请重新登录',
          code: 401,
        );
      }
      final pair = TokenPair.fromJson(body['data'] as Map<String, dynamic>);
      if (pair.accessToken.isEmpty || pair.refreshToken.isEmpty) {
        throw ApiException('刷新登录态失败', code: 401);
      }
      _tokens.accessToken = pair.accessToken;
      await _tokens.saveRefreshToken(pair.refreshToken);
      _authLostNotified = false;
      return pair;
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  /// 通知 App 层登录态失效（只触发一次）
  Future<void> _notifyAuthLost() async {
    await _tokens.clear();
    if (_authLostNotified) return;
    _authLostNotified = true;
    onAuthLost?.call();
  }

  /// GET 请求，返回统一响应中的 data 字段
  Future<dynamic> getJson(String path, {Map<String, dynamic>? query}) async {
    try {
      final response = await _dio.get(path, queryParameters: query);
      return _unwrap(response);
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  /// GET 请求，返回原始响应体（用于未包统一 Response 的接口，如聊天历史）
  Future<dynamic> getRaw(String path, {Map<String, dynamic>? query}) async {
    try {
      final response = await _dio.get(path, queryParameters: query);
      return response.data;
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  /// POST 请求，返回统一响应中的 data 字段
  Future<dynamic> postJson(String path, {Object? data}) async {
    try {
      final response = await _dio.post(path, data: data);
      return _unwrap(response);
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  /// 解包 `{code, message, data}`，code != 0 抛业务异常
  dynamic _unwrap(Response<dynamic> response) {
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw ApiException('响应格式异常');
    }
    final code = (body['code'] as num?)?.toInt() ?? -1;
    if (code != 0) {
      throw ApiException((body['message'] as String?) ?? '请求失败', code: code);
    }
    return body['data'];
  }

  /// 把 DioException 转成可展示的中文异常
  ApiException _toApiException(DioException e) {
    final body = e.response?.data;
    if (body is Map<String, dynamic>) {
      final message = body['message'];
      if (message is String && message.isNotEmpty) {
        return ApiException(message, code: (body['code'] as num?)?.toInt());
      }
    }
    final status = e.response?.statusCode;
    if (status == 401) return ApiException('登录已过期，请重新登录', code: 401);
    if (status == 403) return ApiException('没有权限访问该会议', code: 403);
    if (status == 404) return ApiException('会议不存在或已被删除', code: 404);
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException('网络超时，请检查网络后重试');
      case DioExceptionType.connectionError:
        return ApiException('无法连接服务器，请确认手机与服务器在同一网络');
      case DioExceptionType.badCertificate:
        return ApiException('服务器证书不受信任');
      default:
        return ApiException('网络请求失败，请稍后重试');
    }
  }
}

/// ApiClient Provider
final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  final tokens = ref.watch(tokenStorageProvider);
  return ApiClient(config: config, tokens: tokens);
});
