// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'types.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TypstrxError {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TypstrxError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TypstrxError()';
}


}

/// @nodoc
class $TypstrxErrorCopyWith<$Res>  {
$TypstrxErrorCopyWith(TypstrxError _, $Res Function(TypstrxError) __);
}


/// Adds pattern-matching-related methods to [TypstrxError].
extension TypstrxErrorPatterns on TypstrxError {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( TypstrxError_Stale value)?  stale,TResult Function( TypstrxError_NoDocument value)?  noDocument,TResult Function( TypstrxError_PageOutOfRange value)?  pageOutOfRange,TResult Function( TypstrxError_RenderTooLarge value)?  renderTooLarge,TResult Function( TypstrxError_Other value)?  other,required TResult orElse(),}){
final _that = this;
switch (_that) {
case TypstrxError_Stale() when stale != null:
return stale(_that);case TypstrxError_NoDocument() when noDocument != null:
return noDocument(_that);case TypstrxError_PageOutOfRange() when pageOutOfRange != null:
return pageOutOfRange(_that);case TypstrxError_RenderTooLarge() when renderTooLarge != null:
return renderTooLarge(_that);case TypstrxError_Other() when other != null:
return other(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( TypstrxError_Stale value)  stale,required TResult Function( TypstrxError_NoDocument value)  noDocument,required TResult Function( TypstrxError_PageOutOfRange value)  pageOutOfRange,required TResult Function( TypstrxError_RenderTooLarge value)  renderTooLarge,required TResult Function( TypstrxError_Other value)  other,}){
final _that = this;
switch (_that) {
case TypstrxError_Stale():
return stale(_that);case TypstrxError_NoDocument():
return noDocument(_that);case TypstrxError_PageOutOfRange():
return pageOutOfRange(_that);case TypstrxError_RenderTooLarge():
return renderTooLarge(_that);case TypstrxError_Other():
return other(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( TypstrxError_Stale value)?  stale,TResult? Function( TypstrxError_NoDocument value)?  noDocument,TResult? Function( TypstrxError_PageOutOfRange value)?  pageOutOfRange,TResult? Function( TypstrxError_RenderTooLarge value)?  renderTooLarge,TResult? Function( TypstrxError_Other value)?  other,}){
final _that = this;
switch (_that) {
case TypstrxError_Stale() when stale != null:
return stale(_that);case TypstrxError_NoDocument() when noDocument != null:
return noDocument(_that);case TypstrxError_PageOutOfRange() when pageOutOfRange != null:
return pageOutOfRange(_that);case TypstrxError_RenderTooLarge() when renderTooLarge != null:
return renderTooLarge(_that);case TypstrxError_Other() when other != null:
return other(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  stale,TResult Function()?  noDocument,TResult Function( int pageCount)?  pageOutOfRange,TResult Function( String message)?  renderTooLarge,TResult Function( String message)?  other,required TResult orElse(),}) {final _that = this;
switch (_that) {
case TypstrxError_Stale() when stale != null:
return stale();case TypstrxError_NoDocument() when noDocument != null:
return noDocument();case TypstrxError_PageOutOfRange() when pageOutOfRange != null:
return pageOutOfRange(_that.pageCount);case TypstrxError_RenderTooLarge() when renderTooLarge != null:
return renderTooLarge(_that.message);case TypstrxError_Other() when other != null:
return other(_that.message);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  stale,required TResult Function()  noDocument,required TResult Function( int pageCount)  pageOutOfRange,required TResult Function( String message)  renderTooLarge,required TResult Function( String message)  other,}) {final _that = this;
switch (_that) {
case TypstrxError_Stale():
return stale();case TypstrxError_NoDocument():
return noDocument();case TypstrxError_PageOutOfRange():
return pageOutOfRange(_that.pageCount);case TypstrxError_RenderTooLarge():
return renderTooLarge(_that.message);case TypstrxError_Other():
return other(_that.message);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  stale,TResult? Function()?  noDocument,TResult? Function( int pageCount)?  pageOutOfRange,TResult? Function( String message)?  renderTooLarge,TResult? Function( String message)?  other,}) {final _that = this;
switch (_that) {
case TypstrxError_Stale() when stale != null:
return stale();case TypstrxError_NoDocument() when noDocument != null:
return noDocument();case TypstrxError_PageOutOfRange() when pageOutOfRange != null:
return pageOutOfRange(_that.pageCount);case TypstrxError_RenderTooLarge() when renderTooLarge != null:
return renderTooLarge(_that.message);case TypstrxError_Other() when other != null:
return other(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class TypstrxError_Stale extends TypstrxError {
  const TypstrxError_Stale(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TypstrxError_Stale);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TypstrxError.stale()';
}


}




/// @nodoc


class TypstrxError_NoDocument extends TypstrxError {
  const TypstrxError_NoDocument(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TypstrxError_NoDocument);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TypstrxError.noDocument()';
}


}




/// @nodoc


class TypstrxError_PageOutOfRange extends TypstrxError {
  const TypstrxError_PageOutOfRange({required this.pageCount}): super._();
  

 final  int pageCount;

/// Create a copy of TypstrxError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TypstrxError_PageOutOfRangeCopyWith<TypstrxError_PageOutOfRange> get copyWith => _$TypstrxError_PageOutOfRangeCopyWithImpl<TypstrxError_PageOutOfRange>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TypstrxError_PageOutOfRange&&(identical(other.pageCount, pageCount) || other.pageCount == pageCount));
}


@override
int get hashCode => Object.hash(runtimeType,pageCount);

@override
String toString() {
  return 'TypstrxError.pageOutOfRange(pageCount: $pageCount)';
}


}

/// @nodoc
abstract mixin class $TypstrxError_PageOutOfRangeCopyWith<$Res> implements $TypstrxErrorCopyWith<$Res> {
  factory $TypstrxError_PageOutOfRangeCopyWith(TypstrxError_PageOutOfRange value, $Res Function(TypstrxError_PageOutOfRange) _then) = _$TypstrxError_PageOutOfRangeCopyWithImpl;
@useResult
$Res call({
 int pageCount
});




}
/// @nodoc
class _$TypstrxError_PageOutOfRangeCopyWithImpl<$Res>
    implements $TypstrxError_PageOutOfRangeCopyWith<$Res> {
  _$TypstrxError_PageOutOfRangeCopyWithImpl(this._self, this._then);

  final TypstrxError_PageOutOfRange _self;
  final $Res Function(TypstrxError_PageOutOfRange) _then;

/// Create a copy of TypstrxError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? pageCount = null,}) {
  return _then(TypstrxError_PageOutOfRange(
pageCount: null == pageCount ? _self.pageCount : pageCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class TypstrxError_RenderTooLarge extends TypstrxError {
  const TypstrxError_RenderTooLarge({required this.message}): super._();
  

 final  String message;

/// Create a copy of TypstrxError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TypstrxError_RenderTooLargeCopyWith<TypstrxError_RenderTooLarge> get copyWith => _$TypstrxError_RenderTooLargeCopyWithImpl<TypstrxError_RenderTooLarge>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TypstrxError_RenderTooLarge&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'TypstrxError.renderTooLarge(message: $message)';
}


}

/// @nodoc
abstract mixin class $TypstrxError_RenderTooLargeCopyWith<$Res> implements $TypstrxErrorCopyWith<$Res> {
  factory $TypstrxError_RenderTooLargeCopyWith(TypstrxError_RenderTooLarge value, $Res Function(TypstrxError_RenderTooLarge) _then) = _$TypstrxError_RenderTooLargeCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$TypstrxError_RenderTooLargeCopyWithImpl<$Res>
    implements $TypstrxError_RenderTooLargeCopyWith<$Res> {
  _$TypstrxError_RenderTooLargeCopyWithImpl(this._self, this._then);

  final TypstrxError_RenderTooLarge _self;
  final $Res Function(TypstrxError_RenderTooLarge) _then;

/// Create a copy of TypstrxError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(TypstrxError_RenderTooLarge(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class TypstrxError_Other extends TypstrxError {
  const TypstrxError_Other({required this.message}): super._();
  

 final  String message;

/// Create a copy of TypstrxError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TypstrxError_OtherCopyWith<TypstrxError_Other> get copyWith => _$TypstrxError_OtherCopyWithImpl<TypstrxError_Other>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TypstrxError_Other&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'TypstrxError.other(message: $message)';
}


}

/// @nodoc
abstract mixin class $TypstrxError_OtherCopyWith<$Res> implements $TypstrxErrorCopyWith<$Res> {
  factory $TypstrxError_OtherCopyWith(TypstrxError_Other value, $Res Function(TypstrxError_Other) _then) = _$TypstrxError_OtherCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$TypstrxError_OtherCopyWithImpl<$Res>
    implements $TypstrxError_OtherCopyWith<$Res> {
  _$TypstrxError_OtherCopyWithImpl(this._self, this._then);

  final TypstrxError_Other _self;
  final $Res Function(TypstrxError_Other) _then;

/// Create a copy of TypstrxError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(TypstrxError_Other(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
