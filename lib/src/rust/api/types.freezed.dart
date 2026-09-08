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
mixin _$TypstCompletionKind {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TypstCompletionKind);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TypstCompletionKind()';
}


}

/// @nodoc
class $TypstCompletionKindCopyWith<$Res>  {
$TypstCompletionKindCopyWith(TypstCompletionKind _, $Res Function(TypstCompletionKind) __);
}


/// Adds pattern-matching-related methods to [TypstCompletionKind].
extension TypstCompletionKindPatterns on TypstCompletionKind {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( TypstCompletionKind_Syntax value)?  syntax,TResult Function( TypstCompletionKind_Func value)?  func,TResult Function( TypstCompletionKind_Type value)?  type,TResult Function( TypstCompletionKind_Param value)?  param,TResult Function( TypstCompletionKind_Constant value)?  constant,TResult Function( TypstCompletionKind_Path value)?  path,TResult Function( TypstCompletionKind_Package value)?  package,TResult Function( TypstCompletionKind_Label value)?  label,TResult Function( TypstCompletionKind_Font value)?  font,TResult Function( TypstCompletionKind_Symbol value)?  symbol,required TResult orElse(),}){
final _that = this;
switch (_that) {
case TypstCompletionKind_Syntax() when syntax != null:
return syntax(_that);case TypstCompletionKind_Func() when func != null:
return func(_that);case TypstCompletionKind_Type() when type != null:
return type(_that);case TypstCompletionKind_Param() when param != null:
return param(_that);case TypstCompletionKind_Constant() when constant != null:
return constant(_that);case TypstCompletionKind_Path() when path != null:
return path(_that);case TypstCompletionKind_Package() when package != null:
return package(_that);case TypstCompletionKind_Label() when label != null:
return label(_that);case TypstCompletionKind_Font() when font != null:
return font(_that);case TypstCompletionKind_Symbol() when symbol != null:
return symbol(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( TypstCompletionKind_Syntax value)  syntax,required TResult Function( TypstCompletionKind_Func value)  func,required TResult Function( TypstCompletionKind_Type value)  type,required TResult Function( TypstCompletionKind_Param value)  param,required TResult Function( TypstCompletionKind_Constant value)  constant,required TResult Function( TypstCompletionKind_Path value)  path,required TResult Function( TypstCompletionKind_Package value)  package,required TResult Function( TypstCompletionKind_Label value)  label,required TResult Function( TypstCompletionKind_Font value)  font,required TResult Function( TypstCompletionKind_Symbol value)  symbol,}){
final _that = this;
switch (_that) {
case TypstCompletionKind_Syntax():
return syntax(_that);case TypstCompletionKind_Func():
return func(_that);case TypstCompletionKind_Type():
return type(_that);case TypstCompletionKind_Param():
return param(_that);case TypstCompletionKind_Constant():
return constant(_that);case TypstCompletionKind_Path():
return path(_that);case TypstCompletionKind_Package():
return package(_that);case TypstCompletionKind_Label():
return label(_that);case TypstCompletionKind_Font():
return font(_that);case TypstCompletionKind_Symbol():
return symbol(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( TypstCompletionKind_Syntax value)?  syntax,TResult? Function( TypstCompletionKind_Func value)?  func,TResult? Function( TypstCompletionKind_Type value)?  type,TResult? Function( TypstCompletionKind_Param value)?  param,TResult? Function( TypstCompletionKind_Constant value)?  constant,TResult? Function( TypstCompletionKind_Path value)?  path,TResult? Function( TypstCompletionKind_Package value)?  package,TResult? Function( TypstCompletionKind_Label value)?  label,TResult? Function( TypstCompletionKind_Font value)?  font,TResult? Function( TypstCompletionKind_Symbol value)?  symbol,}){
final _that = this;
switch (_that) {
case TypstCompletionKind_Syntax() when syntax != null:
return syntax(_that);case TypstCompletionKind_Func() when func != null:
return func(_that);case TypstCompletionKind_Type() when type != null:
return type(_that);case TypstCompletionKind_Param() when param != null:
return param(_that);case TypstCompletionKind_Constant() when constant != null:
return constant(_that);case TypstCompletionKind_Path() when path != null:
return path(_that);case TypstCompletionKind_Package() when package != null:
return package(_that);case TypstCompletionKind_Label() when label != null:
return label(_that);case TypstCompletionKind_Font() when font != null:
return font(_that);case TypstCompletionKind_Symbol() when symbol != null:
return symbol(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  syntax,TResult Function()?  func,TResult Function()?  type,TResult Function()?  param,TResult Function()?  constant,TResult Function()?  path,TResult Function()?  package,TResult Function()?  label,TResult Function()?  font,TResult Function( String notation)?  symbol,required TResult orElse(),}) {final _that = this;
switch (_that) {
case TypstCompletionKind_Syntax() when syntax != null:
return syntax();case TypstCompletionKind_Func() when func != null:
return func();case TypstCompletionKind_Type() when type != null:
return type();case TypstCompletionKind_Param() when param != null:
return param();case TypstCompletionKind_Constant() when constant != null:
return constant();case TypstCompletionKind_Path() when path != null:
return path();case TypstCompletionKind_Package() when package != null:
return package();case TypstCompletionKind_Label() when label != null:
return label();case TypstCompletionKind_Font() when font != null:
return font();case TypstCompletionKind_Symbol() when symbol != null:
return symbol(_that.notation);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  syntax,required TResult Function()  func,required TResult Function()  type,required TResult Function()  param,required TResult Function()  constant,required TResult Function()  path,required TResult Function()  package,required TResult Function()  label,required TResult Function()  font,required TResult Function( String notation)  symbol,}) {final _that = this;
switch (_that) {
case TypstCompletionKind_Syntax():
return syntax();case TypstCompletionKind_Func():
return func();case TypstCompletionKind_Type():
return type();case TypstCompletionKind_Param():
return param();case TypstCompletionKind_Constant():
return constant();case TypstCompletionKind_Path():
return path();case TypstCompletionKind_Package():
return package();case TypstCompletionKind_Label():
return label();case TypstCompletionKind_Font():
return font();case TypstCompletionKind_Symbol():
return symbol(_that.notation);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  syntax,TResult? Function()?  func,TResult? Function()?  type,TResult? Function()?  param,TResult? Function()?  constant,TResult? Function()?  path,TResult? Function()?  package,TResult? Function()?  label,TResult? Function()?  font,TResult? Function( String notation)?  symbol,}) {final _that = this;
switch (_that) {
case TypstCompletionKind_Syntax() when syntax != null:
return syntax();case TypstCompletionKind_Func() when func != null:
return func();case TypstCompletionKind_Type() when type != null:
return type();case TypstCompletionKind_Param() when param != null:
return param();case TypstCompletionKind_Constant() when constant != null:
return constant();case TypstCompletionKind_Path() when path != null:
return path();case TypstCompletionKind_Package() when package != null:
return package();case TypstCompletionKind_Label() when label != null:
return label();case TypstCompletionKind_Font() when font != null:
return font();case TypstCompletionKind_Symbol() when symbol != null:
return symbol(_that.notation);case _:
  return null;

}
}

}

/// @nodoc


class TypstCompletionKind_Syntax extends TypstCompletionKind {
  const TypstCompletionKind_Syntax(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TypstCompletionKind_Syntax);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TypstCompletionKind.syntax()';
}


}




/// @nodoc


class TypstCompletionKind_Func extends TypstCompletionKind {
  const TypstCompletionKind_Func(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TypstCompletionKind_Func);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TypstCompletionKind.func()';
}


}




/// @nodoc


class TypstCompletionKind_Type extends TypstCompletionKind {
  const TypstCompletionKind_Type(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TypstCompletionKind_Type);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TypstCompletionKind.type()';
}


}




/// @nodoc


class TypstCompletionKind_Param extends TypstCompletionKind {
  const TypstCompletionKind_Param(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TypstCompletionKind_Param);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TypstCompletionKind.param()';
}


}




/// @nodoc


class TypstCompletionKind_Constant extends TypstCompletionKind {
  const TypstCompletionKind_Constant(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TypstCompletionKind_Constant);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TypstCompletionKind.constant()';
}


}




/// @nodoc


class TypstCompletionKind_Path extends TypstCompletionKind {
  const TypstCompletionKind_Path(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TypstCompletionKind_Path);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TypstCompletionKind.path()';
}


}




/// @nodoc


class TypstCompletionKind_Package extends TypstCompletionKind {
  const TypstCompletionKind_Package(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TypstCompletionKind_Package);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TypstCompletionKind.package()';
}


}




/// @nodoc


class TypstCompletionKind_Label extends TypstCompletionKind {
  const TypstCompletionKind_Label(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TypstCompletionKind_Label);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TypstCompletionKind.label()';
}


}




/// @nodoc


class TypstCompletionKind_Font extends TypstCompletionKind {
  const TypstCompletionKind_Font(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TypstCompletionKind_Font);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TypstCompletionKind.font()';
}


}




/// @nodoc


class TypstCompletionKind_Symbol extends TypstCompletionKind {
  const TypstCompletionKind_Symbol({required this.notation}): super._();
  

 final  String notation;

/// Create a copy of TypstCompletionKind
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TypstCompletionKind_SymbolCopyWith<TypstCompletionKind_Symbol> get copyWith => _$TypstCompletionKind_SymbolCopyWithImpl<TypstCompletionKind_Symbol>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TypstCompletionKind_Symbol&&(identical(other.notation, notation) || other.notation == notation));
}


@override
int get hashCode => Object.hash(runtimeType,notation);

@override
String toString() {
  return 'TypstCompletionKind.symbol(notation: $notation)';
}


}

/// @nodoc
abstract mixin class $TypstCompletionKind_SymbolCopyWith<$Res> implements $TypstCompletionKindCopyWith<$Res> {
  factory $TypstCompletionKind_SymbolCopyWith(TypstCompletionKind_Symbol value, $Res Function(TypstCompletionKind_Symbol) _then) = _$TypstCompletionKind_SymbolCopyWithImpl;
@useResult
$Res call({
 String notation
});




}
/// @nodoc
class _$TypstCompletionKind_SymbolCopyWithImpl<$Res>
    implements $TypstCompletionKind_SymbolCopyWith<$Res> {
  _$TypstCompletionKind_SymbolCopyWithImpl(this._self, this._then);

  final TypstCompletionKind_Symbol _self;
  final $Res Function(TypstCompletionKind_Symbol) _then;

/// Create a copy of TypstCompletionKind
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? notation = null,}) {
  return _then(TypstCompletionKind_Symbol(
notation: null == notation ? _self.notation : notation // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$TypstTooltip {

 String get content;
/// Create a copy of TypstTooltip
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TypstTooltipCopyWith<TypstTooltip> get copyWith => _$TypstTooltipCopyWithImpl<TypstTooltip>(this as TypstTooltip, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TypstTooltip&&(identical(other.content, content) || other.content == content));
}


@override
int get hashCode => Object.hash(runtimeType,content);

@override
String toString() {
  return 'TypstTooltip(content: $content)';
}


}

/// @nodoc
abstract mixin class $TypstTooltipCopyWith<$Res>  {
  factory $TypstTooltipCopyWith(TypstTooltip value, $Res Function(TypstTooltip) _then) = _$TypstTooltipCopyWithImpl;
@useResult
$Res call({
 String content
});




}
/// @nodoc
class _$TypstTooltipCopyWithImpl<$Res>
    implements $TypstTooltipCopyWith<$Res> {
  _$TypstTooltipCopyWithImpl(this._self, this._then);

  final TypstTooltip _self;
  final $Res Function(TypstTooltip) _then;

/// Create a copy of TypstTooltip
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? content = null,}) {
  return _then(_self.copyWith(
content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [TypstTooltip].
extension TypstTooltipPatterns on TypstTooltip {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( TypstTooltip_Text value)?  text,TResult Function( TypstTooltip_Code value)?  code,required TResult orElse(),}){
final _that = this;
switch (_that) {
case TypstTooltip_Text() when text != null:
return text(_that);case TypstTooltip_Code() when code != null:
return code(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( TypstTooltip_Text value)  text,required TResult Function( TypstTooltip_Code value)  code,}){
final _that = this;
switch (_that) {
case TypstTooltip_Text():
return text(_that);case TypstTooltip_Code():
return code(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( TypstTooltip_Text value)?  text,TResult? Function( TypstTooltip_Code value)?  code,}){
final _that = this;
switch (_that) {
case TypstTooltip_Text() when text != null:
return text(_that);case TypstTooltip_Code() when code != null:
return code(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String content)?  text,TResult Function( String content)?  code,required TResult orElse(),}) {final _that = this;
switch (_that) {
case TypstTooltip_Text() when text != null:
return text(_that.content);case TypstTooltip_Code() when code != null:
return code(_that.content);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String content)  text,required TResult Function( String content)  code,}) {final _that = this;
switch (_that) {
case TypstTooltip_Text():
return text(_that.content);case TypstTooltip_Code():
return code(_that.content);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String content)?  text,TResult? Function( String content)?  code,}) {final _that = this;
switch (_that) {
case TypstTooltip_Text() when text != null:
return text(_that.content);case TypstTooltip_Code() when code != null:
return code(_that.content);case _:
  return null;

}
}

}

/// @nodoc


class TypstTooltip_Text extends TypstTooltip {
  const TypstTooltip_Text({required this.content}): super._();
  

@override final  String content;

/// Create a copy of TypstTooltip
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TypstTooltip_TextCopyWith<TypstTooltip_Text> get copyWith => _$TypstTooltip_TextCopyWithImpl<TypstTooltip_Text>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TypstTooltip_Text&&(identical(other.content, content) || other.content == content));
}


@override
int get hashCode => Object.hash(runtimeType,content);

@override
String toString() {
  return 'TypstTooltip.text(content: $content)';
}


}

/// @nodoc
abstract mixin class $TypstTooltip_TextCopyWith<$Res> implements $TypstTooltipCopyWith<$Res> {
  factory $TypstTooltip_TextCopyWith(TypstTooltip_Text value, $Res Function(TypstTooltip_Text) _then) = _$TypstTooltip_TextCopyWithImpl;
@override @useResult
$Res call({
 String content
});




}
/// @nodoc
class _$TypstTooltip_TextCopyWithImpl<$Res>
    implements $TypstTooltip_TextCopyWith<$Res> {
  _$TypstTooltip_TextCopyWithImpl(this._self, this._then);

  final TypstTooltip_Text _self;
  final $Res Function(TypstTooltip_Text) _then;

/// Create a copy of TypstTooltip
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? content = null,}) {
  return _then(TypstTooltip_Text(
content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class TypstTooltip_Code extends TypstTooltip {
  const TypstTooltip_Code({required this.content}): super._();
  

@override final  String content;

/// Create a copy of TypstTooltip
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TypstTooltip_CodeCopyWith<TypstTooltip_Code> get copyWith => _$TypstTooltip_CodeCopyWithImpl<TypstTooltip_Code>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TypstTooltip_Code&&(identical(other.content, content) || other.content == content));
}


@override
int get hashCode => Object.hash(runtimeType,content);

@override
String toString() {
  return 'TypstTooltip.code(content: $content)';
}


}

/// @nodoc
abstract mixin class $TypstTooltip_CodeCopyWith<$Res> implements $TypstTooltipCopyWith<$Res> {
  factory $TypstTooltip_CodeCopyWith(TypstTooltip_Code value, $Res Function(TypstTooltip_Code) _then) = _$TypstTooltip_CodeCopyWithImpl;
@override @useResult
$Res call({
 String content
});




}
/// @nodoc
class _$TypstTooltip_CodeCopyWithImpl<$Res>
    implements $TypstTooltip_CodeCopyWith<$Res> {
  _$TypstTooltip_CodeCopyWithImpl(this._self, this._then);

  final TypstTooltip_Code _self;
  final $Res Function(TypstTooltip_Code) _then;

/// Create a copy of TypstTooltip
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? content = null,}) {
  return _then(TypstTooltip_Code(
content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

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
