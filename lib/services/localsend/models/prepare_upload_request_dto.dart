import 'file_dto.dart';
import 'info_register_dto.dart';

class PrepareUploadRequestDto {
  final InfoRegisterDto info;
  final Map<String, FileDto> files;

  const PrepareUploadRequestDto({
    required this.info,
    required this.files,
  });

  Map<String, dynamic> toJson() {
    return {
      'info': info.toJson(),
      'files': files.map((key, value) => MapEntry(key, value.toJson())),
    };
  }

  static PrepareUploadRequestDto fromJson(Map<String, dynamic> json) {
    return PrepareUploadRequestDto(
      info: InfoRegisterDto.fromJson(json['info'] as Map<String, dynamic>),
      files: (json['files'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, FileDto.fromJson(value as Map<String, dynamic>)),
      ),
    );
  }
}
