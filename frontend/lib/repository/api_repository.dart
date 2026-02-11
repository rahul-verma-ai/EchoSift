import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

class SessionExpiredException implements Exception {}

class ApiRepository {
  final Dio _dio;

  ApiRepository()
      : _dio = Dio(
          BaseOptions(
            baseUrl: 'https://subelongate-unsolvably-cristie.ngrok-free.dev',
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(minutes: 5),
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) {
          if (error.response?.statusCode == 401) {
            handler.reject(
              DioException(
                requestOptions: error.requestOptions,
                error: SessionExpiredException(),
              ),
            );
            return;
          }
          handler.next(error);
        },
      ),
    );
  }

  /// Creates a backend session and returns session_id
  Future<String> createSession() async {
    try {
      final response = await _dio.post('/session');
      final sessionId = response.data['session_id'] as String?;
      if (sessionId == null || sessionId.isEmpty) {
        throw Exception('Invalid session_id');
      }
      return sessionId;
    } on DioException catch (e) {
      if (e.error is SessionExpiredException) {
        throw SessionExpiredException();
      }
      if (_isTimeout(e)) {
        throw TimeoutException('timeout');
      }
      rethrow;
    }
  }

  /// Uploads audio and returns AI emotional mirror text
  Future<String> uploadVent({
    required String sessionId,
    required File audioFile,
  }) async {
    try {
      // 1. Validate file exists and isn't empty
      if (!await audioFile.exists() || await audioFile.length() == 0) {
        throw Exception("Audio file is missing or empty");
      }

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          audioFile.path,
          filename: 'vent_${DateTime.now().millisecondsSinceEpoch}.m4a',
        ),
      });

      // 2. Override timeouts for this specific heavy-duty call
      final response = await _dio.post(
        '/session/$sessionId/audio',
        data: formData,
        options: Options(
          sendTimeout: const Duration(seconds: 30), // Time to upload
          receiveTimeout: const Duration(seconds: 90), // Time for STT + LLM
        ),
        onSendProgress: (count, total) {
          final progress = (count / total * 100).toStringAsFixed(0);
          print('Uploading: $progress%');
        },
      );

      // 3. Robust response parsing
      if (response.statusCode == 200 && response.data != null) {
        // Adapt this key based on your Python backend's return JSON
        return response.data['response']?.toString() ??
            response.data['analysis']?.toString() ??
            '';
      }

      return '';
    } on DioException catch (e) {
      print('Dio Error: ${e.type} - ${e.message}');

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw TimeoutException(
            'The AI is taking a moment to sift through your feelings. Please wait.');
      }

      if (e.response?.statusCode == 401) {
        throw SessionExpiredException();
      }

      rethrow;
    } catch (e) {
      print('Unexpected Error: $e');
      rethrow;
    }
  }

  bool _isTimeout(DioException e) =>
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout;
}
