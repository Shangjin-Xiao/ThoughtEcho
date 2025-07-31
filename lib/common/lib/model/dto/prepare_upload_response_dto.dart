import 'dart:convert';
import 'package:dart_mappable/dart_mappable.dart';

part 'prepare_upload_response_dto.mapper.dart';

@MappableClass()
class PrepareUploadResponseDto with PrepareUploadResponseDtoMappable {
  final String sessionId;
  final Map<String, String> files;

  const PrepareUploadResponseDto({
    required this.sessionId,
    required this.files,
  });

  factory PrepareUploadResponseDto.fromJson(String jsonString) {
    try {
      // Try to parse as JSON object first
      final Map<String, dynamic> json = jsonDecode(jsonString);
      return PrepareUploadResponseDto(
        sessionId: json['sessionId'] as String,
        files: Map<String, String>.from(json['files'] as Map),
      );
    } catch (e) {
      // Fallback to direct file token map for legacy support
      final Map<String, String> files = Map<String, String>.from(
        jsonDecode(jsonString) as Map
      );
      return PrepareUploadResponseDto(
        sessionId: 'legacy_session',
        files: files,
      );
    }
  }

  static const fromJson = PrepareUploadResponseDtoMapper.fromJson;
}
