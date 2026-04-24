import 'dart:io';
import 'package:dio/dio.dart';
import 'package:orka_sports/core/utils/app_exception.dart';

class ErrorHandler {
  static AppException handleError(dynamic error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return TimeoutException();
        case DioExceptionType.badResponse:
          return ServerException();
        case DioExceptionType.connectionError:
          return NetworkException();
        default:
          return UnknownException();
      }
    }
    
    if (error is SocketException) {
      return NetworkException();
    } else if (error is HttpException) {
      return ServerException();
    } else {
      return UnknownException();
    }
  }
}
