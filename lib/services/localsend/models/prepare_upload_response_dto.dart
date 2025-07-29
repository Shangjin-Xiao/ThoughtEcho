class PrepareUploadResponseDto {
  final String sessionId;
  final Map<String, String> files;

  const PrepareUploadResponseDto({
    required this.sessionId,
    required this.files,
  });

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'files': files,
    };
  }

  static PrepareUploadResponseDto fromJson(Map<String, dynamic> json) {
    return PrepareUploadResponseDto(
      sessionId: json['sessionId'] as String,
      files: Map<String, String>.from(json['files'] as Map),
    );
  }
}
