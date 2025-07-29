// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'prepare_upload_request_dto.dart';

class PrepareUploadRequestDtoMapper
    extends ClassMapperBase<PrepareUploadRequestDto> {
  PrepareUploadRequestDtoMapper._();

  static PrepareUploadRequestDtoMapper? _instance;
  static PrepareUploadRequestDtoMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals
          .use(_instance = PrepareUploadRequestDtoMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'PrepareUploadRequestDto';

  static InvalidType _$info(PrepareUploadRequestDto v) => v.info;
  static const Field<PrepareUploadRequestDto, InvalidType> _f$info =
      Field('info', _$info);
  static Map<String, InvalidType> _$files(PrepareUploadRequestDto v) => v.files;
  static const Field<PrepareUploadRequestDto, Map<String, InvalidType>>
      _f$files = Field('files', _$files);

  @override
  final MappableFields<PrepareUploadRequestDto> fields = const {
    #info: _f$info,
    #files: _f$files,
  };

  static PrepareUploadRequestDto _instantiate(DecodingData data) {
    return PrepareUploadRequestDto(
        info: data.dec(_f$info), files: data.dec(_f$files));
  }

  @override
  final Function instantiate = _instantiate;

  static PrepareUploadRequestDto fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PrepareUploadRequestDto>(map);
  }

  static PrepareUploadRequestDto fromJson(String json) {
    return ensureInitialized().decodeJson<PrepareUploadRequestDto>(json);
  }
}

mixin PrepareUploadRequestDtoMappable {
  String toJson() {
    return PrepareUploadRequestDtoMapper.ensureInitialized()
        .encodeJson<PrepareUploadRequestDto>(this as PrepareUploadRequestDto);
  }

  Map<String, dynamic> toMap() {
    return PrepareUploadRequestDtoMapper.ensureInitialized()
        .encodeMap<PrepareUploadRequestDto>(this as PrepareUploadRequestDto);
  }

  PrepareUploadRequestDtoCopyWith<PrepareUploadRequestDto,
          PrepareUploadRequestDto, PrepareUploadRequestDto>
      get copyWith => _PrepareUploadRequestDtoCopyWithImpl(
          this as PrepareUploadRequestDto, $identity, $identity);
  @override
  String toString() {
    return PrepareUploadRequestDtoMapper.ensureInitialized()
        .stringifyValue(this as PrepareUploadRequestDto);
  }

  @override
  bool operator ==(Object other) {
    return PrepareUploadRequestDtoMapper.ensureInitialized()
        .equalsValue(this as PrepareUploadRequestDto, other);
  }

  @override
  int get hashCode {
    return PrepareUploadRequestDtoMapper.ensureInitialized()
        .hashValue(this as PrepareUploadRequestDto);
  }
}

extension PrepareUploadRequestDtoValueCopy<$R, $Out>
    on ObjectCopyWith<$R, PrepareUploadRequestDto, $Out> {
  PrepareUploadRequestDtoCopyWith<$R, PrepareUploadRequestDto, $Out>
      get $asPrepareUploadRequestDto => $base
          .as((v, t, t2) => _PrepareUploadRequestDtoCopyWithImpl(v, t, t2));
}

abstract class PrepareUploadRequestDtoCopyWith<
    $R,
    $In extends PrepareUploadRequestDto,
    $Out> implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, InvalidType,
      ObjectCopyWith<$R, InvalidType, InvalidType>> get files;
  $R call({InvalidType? info, Map<String, InvalidType>? files});
  PrepareUploadRequestDtoCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
      Then<$Out2, $R2> t);
}

class _PrepareUploadRequestDtoCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, PrepareUploadRequestDto, $Out>
    implements
        PrepareUploadRequestDtoCopyWith<$R, PrepareUploadRequestDto, $Out> {
  _PrepareUploadRequestDtoCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<PrepareUploadRequestDto> $mapper =
      PrepareUploadRequestDtoMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, InvalidType,
          ObjectCopyWith<$R, InvalidType, InvalidType>>
      get files => MapCopyWith($value.files,
          (v, t) => ObjectCopyWith(v, $identity, t), (v) => call(files: v));
  @override
  $R call({InvalidType? info, Map<String, InvalidType>? files}) =>
      $apply(FieldCopyWithData(
          {if (info != null) #info: info, if (files != null) #files: files}));
  @override
  PrepareUploadRequestDto $make(CopyWithData data) => PrepareUploadRequestDto(
      info: data.get(#info, or: $value.info),
      files: data.get(#files, or: $value.files));

  @override
  PrepareUploadRequestDtoCopyWith<$R2, PrepareUploadRequestDto, $Out2>
      $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
          _PrepareUploadRequestDtoCopyWithImpl($value, $cast, t);
}
