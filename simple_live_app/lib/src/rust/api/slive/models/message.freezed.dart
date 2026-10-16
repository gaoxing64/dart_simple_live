// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'message.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$LiveMessageData {
  Object get field0;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is LiveMessageData &&
            const DeepCollectionEquality().equals(other.field0, field0));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, const DeepCollectionEquality().hash(field0));

  @override
  String toString() {
    return 'LiveMessageData(field0: $field0)';
  }
}

/// @nodoc
class $LiveMessageDataCopyWith<$Res> {
  $LiveMessageDataCopyWith(
      LiveMessageData _, $Res Function(LiveMessageData) __);
}

/// Adds pattern-matching-related methods to [LiveMessageData].
extension LiveMessageDataPatterns on LiveMessageData {
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

  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(LiveMessageData_Online value)? online,
    TResult Function(LiveMessageData_SuperChat value)? superChat,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case LiveMessageData_Online() when online != null:
        return online(_that);
      case LiveMessageData_SuperChat() when superChat != null:
        return superChat(_that);
      case _:
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

  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(LiveMessageData_Online value) online,
    required TResult Function(LiveMessageData_SuperChat value) superChat,
  }) {
    final _that = this;
    switch (_that) {
      case LiveMessageData_Online():
        return online(_that);
      case LiveMessageData_SuperChat():
        return superChat(_that);
    }
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

  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(LiveMessageData_Online value)? online,
    TResult? Function(LiveMessageData_SuperChat value)? superChat,
  }) {
    final _that = this;
    switch (_that) {
      case LiveMessageData_Online() when online != null:
        return online(_that);
      case LiveMessageData_SuperChat() when superChat != null:
        return superChat(_that);
      case _:
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

  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(int field0)? online,
    TResult Function(LiveSuperChatMessage field0)? superChat,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case LiveMessageData_Online() when online != null:
        return online(_that.field0);
      case LiveMessageData_SuperChat() when superChat != null:
        return superChat(_that.field0);
      case _:
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

  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(int field0) online,
    required TResult Function(LiveSuperChatMessage field0) superChat,
  }) {
    final _that = this;
    switch (_that) {
      case LiveMessageData_Online():
        return online(_that.field0);
      case LiveMessageData_SuperChat():
        return superChat(_that.field0);
    }
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

  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(int field0)? online,
    TResult? Function(LiveSuperChatMessage field0)? superChat,
  }) {
    final _that = this;
    switch (_that) {
      case LiveMessageData_Online() when online != null:
        return online(_that.field0);
      case LiveMessageData_SuperChat() when superChat != null:
        return superChat(_that.field0);
      case _:
        return null;
    }
  }
}

/// @nodoc

class LiveMessageData_Online extends LiveMessageData {
  const LiveMessageData_Online(this.field0) : super._();

  @override
  final int field0;

  /// Create a copy of LiveMessageData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $LiveMessageData_OnlineCopyWith<LiveMessageData_Online> get copyWith =>
      _$LiveMessageData_OnlineCopyWithImpl<LiveMessageData_Online>(
          this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is LiveMessageData_Online &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @override
  String toString() {
    return 'LiveMessageData.online(field0: $field0)';
  }
}

/// @nodoc
abstract mixin class $LiveMessageData_OnlineCopyWith<$Res>
    implements $LiveMessageDataCopyWith<$Res> {
  factory $LiveMessageData_OnlineCopyWith(LiveMessageData_Online value,
          $Res Function(LiveMessageData_Online) _then) =
      _$LiveMessageData_OnlineCopyWithImpl;
  @useResult
  $Res call({int field0});
}

/// @nodoc
class _$LiveMessageData_OnlineCopyWithImpl<$Res>
    implements $LiveMessageData_OnlineCopyWith<$Res> {
  _$LiveMessageData_OnlineCopyWithImpl(this._self, this._then);

  final LiveMessageData_Online _self;
  final $Res Function(LiveMessageData_Online) _then;

  /// Create a copy of LiveMessageData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? field0 = null,
  }) {
    return _then(LiveMessageData_Online(
      null == field0
          ? _self.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc

class LiveMessageData_SuperChat extends LiveMessageData {
  const LiveMessageData_SuperChat(this.field0) : super._();

  @override
  final LiveSuperChatMessage field0;

  /// Create a copy of LiveMessageData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $LiveMessageData_SuperChatCopyWith<LiveMessageData_SuperChat> get copyWith =>
      _$LiveMessageData_SuperChatCopyWithImpl<LiveMessageData_SuperChat>(
          this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is LiveMessageData_SuperChat &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @override
  String toString() {
    return 'LiveMessageData.superChat(field0: $field0)';
  }
}

/// @nodoc
abstract mixin class $LiveMessageData_SuperChatCopyWith<$Res>
    implements $LiveMessageDataCopyWith<$Res> {
  factory $LiveMessageData_SuperChatCopyWith(LiveMessageData_SuperChat value,
          $Res Function(LiveMessageData_SuperChat) _then) =
      _$LiveMessageData_SuperChatCopyWithImpl;
  @useResult
  $Res call({LiveSuperChatMessage field0});
}

/// @nodoc
class _$LiveMessageData_SuperChatCopyWithImpl<$Res>
    implements $LiveMessageData_SuperChatCopyWith<$Res> {
  _$LiveMessageData_SuperChatCopyWithImpl(this._self, this._then);

  final LiveMessageData_SuperChat _self;
  final $Res Function(LiveMessageData_SuperChat) _then;

  /// Create a copy of LiveMessageData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? field0 = null,
  }) {
    return _then(LiveMessageData_SuperChat(
      null == field0
          ? _self.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as LiveSuperChatMessage,
    ));
  }
}

// dart format on
