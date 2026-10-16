// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'danmu.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$LiveDanmuControlEvent {
  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is LiveDanmuControlEvent);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'LiveDanmuControlEvent()';
  }
}

/// @nodoc
class $LiveDanmuControlEventCopyWith<$Res> {
  $LiveDanmuControlEventCopyWith(
      LiveDanmuControlEvent _, $Res Function(LiveDanmuControlEvent) __);
}

/// Adds pattern-matching-related methods to [LiveDanmuControlEvent].
extension LiveDanmuControlEventPatterns on LiveDanmuControlEvent {
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
    TResult Function(LiveDanmuControlEvent_Ready value)? ready,
    TResult Function(LiveDanmuControlEvent_Reconnecting value)? reconnecting,
    TResult Function(LiveDanmuControlEvent_Closed value)? closed,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case LiveDanmuControlEvent_Ready() when ready != null:
        return ready(_that);
      case LiveDanmuControlEvent_Reconnecting() when reconnecting != null:
        return reconnecting(_that);
      case LiveDanmuControlEvent_Closed() when closed != null:
        return closed(_that);
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
    required TResult Function(LiveDanmuControlEvent_Ready value) ready,
    required TResult Function(LiveDanmuControlEvent_Reconnecting value)
        reconnecting,
    required TResult Function(LiveDanmuControlEvent_Closed value) closed,
  }) {
    final _that = this;
    switch (_that) {
      case LiveDanmuControlEvent_Ready():
        return ready(_that);
      case LiveDanmuControlEvent_Reconnecting():
        return reconnecting(_that);
      case LiveDanmuControlEvent_Closed():
        return closed(_that);
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
    TResult? Function(LiveDanmuControlEvent_Ready value)? ready,
    TResult? Function(LiveDanmuControlEvent_Reconnecting value)? reconnecting,
    TResult? Function(LiveDanmuControlEvent_Closed value)? closed,
  }) {
    final _that = this;
    switch (_that) {
      case LiveDanmuControlEvent_Ready() when ready != null:
        return ready(_that);
      case LiveDanmuControlEvent_Reconnecting() when reconnecting != null:
        return reconnecting(_that);
      case LiveDanmuControlEvent_Closed() when closed != null:
        return closed(_that);
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
    TResult Function()? ready,
    TResult Function(int attempt)? reconnecting,
    TResult Function(String field0)? closed,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case LiveDanmuControlEvent_Ready() when ready != null:
        return ready();
      case LiveDanmuControlEvent_Reconnecting() when reconnecting != null:
        return reconnecting(_that.attempt);
      case LiveDanmuControlEvent_Closed() when closed != null:
        return closed(_that.field0);
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
    required TResult Function() ready,
    required TResult Function(int attempt) reconnecting,
    required TResult Function(String field0) closed,
  }) {
    final _that = this;
    switch (_that) {
      case LiveDanmuControlEvent_Ready():
        return ready();
      case LiveDanmuControlEvent_Reconnecting():
        return reconnecting(_that.attempt);
      case LiveDanmuControlEvent_Closed():
        return closed(_that.field0);
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
    TResult? Function()? ready,
    TResult? Function(int attempt)? reconnecting,
    TResult? Function(String field0)? closed,
  }) {
    final _that = this;
    switch (_that) {
      case LiveDanmuControlEvent_Ready() when ready != null:
        return ready();
      case LiveDanmuControlEvent_Reconnecting() when reconnecting != null:
        return reconnecting(_that.attempt);
      case LiveDanmuControlEvent_Closed() when closed != null:
        return closed(_that.field0);
      case _:
        return null;
    }
  }
}

/// @nodoc

class LiveDanmuControlEvent_Ready extends LiveDanmuControlEvent {
  const LiveDanmuControlEvent_Ready() : super._();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is LiveDanmuControlEvent_Ready);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'LiveDanmuControlEvent.ready()';
  }
}

/// @nodoc

class LiveDanmuControlEvent_Reconnecting extends LiveDanmuControlEvent {
  const LiveDanmuControlEvent_Reconnecting({required this.attempt}) : super._();

  final int attempt;

  /// Create a copy of LiveDanmuControlEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $LiveDanmuControlEvent_ReconnectingCopyWith<
          LiveDanmuControlEvent_Reconnecting>
      get copyWith => _$LiveDanmuControlEvent_ReconnectingCopyWithImpl<
          LiveDanmuControlEvent_Reconnecting>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is LiveDanmuControlEvent_Reconnecting &&
            (identical(other.attempt, attempt) || other.attempt == attempt));
  }

  @override
  int get hashCode => Object.hash(runtimeType, attempt);

  @override
  String toString() {
    return 'LiveDanmuControlEvent.reconnecting(attempt: $attempt)';
  }
}

/// @nodoc
abstract mixin class $LiveDanmuControlEvent_ReconnectingCopyWith<$Res>
    implements $LiveDanmuControlEventCopyWith<$Res> {
  factory $LiveDanmuControlEvent_ReconnectingCopyWith(
          LiveDanmuControlEvent_Reconnecting value,
          $Res Function(LiveDanmuControlEvent_Reconnecting) _then) =
      _$LiveDanmuControlEvent_ReconnectingCopyWithImpl;
  @useResult
  $Res call({int attempt});
}

/// @nodoc
class _$LiveDanmuControlEvent_ReconnectingCopyWithImpl<$Res>
    implements $LiveDanmuControlEvent_ReconnectingCopyWith<$Res> {
  _$LiveDanmuControlEvent_ReconnectingCopyWithImpl(this._self, this._then);

  final LiveDanmuControlEvent_Reconnecting _self;
  final $Res Function(LiveDanmuControlEvent_Reconnecting) _then;

  /// Create a copy of LiveDanmuControlEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? attempt = null,
  }) {
    return _then(LiveDanmuControlEvent_Reconnecting(
      attempt: null == attempt
          ? _self.attempt
          : attempt // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc

class LiveDanmuControlEvent_Closed extends LiveDanmuControlEvent {
  const LiveDanmuControlEvent_Closed(this.field0) : super._();

  final String field0;

  /// Create a copy of LiveDanmuControlEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $LiveDanmuControlEvent_ClosedCopyWith<LiveDanmuControlEvent_Closed>
      get copyWith => _$LiveDanmuControlEvent_ClosedCopyWithImpl<
          LiveDanmuControlEvent_Closed>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is LiveDanmuControlEvent_Closed &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @override
  String toString() {
    return 'LiveDanmuControlEvent.closed(field0: $field0)';
  }
}

/// @nodoc
abstract mixin class $LiveDanmuControlEvent_ClosedCopyWith<$Res>
    implements $LiveDanmuControlEventCopyWith<$Res> {
  factory $LiveDanmuControlEvent_ClosedCopyWith(
          LiveDanmuControlEvent_Closed value,
          $Res Function(LiveDanmuControlEvent_Closed) _then) =
      _$LiveDanmuControlEvent_ClosedCopyWithImpl;
  @useResult
  $Res call({String field0});
}

/// @nodoc
class _$LiveDanmuControlEvent_ClosedCopyWithImpl<$Res>
    implements $LiveDanmuControlEvent_ClosedCopyWith<$Res> {
  _$LiveDanmuControlEvent_ClosedCopyWithImpl(this._self, this._then);

  final LiveDanmuControlEvent_Closed _self;
  final $Res Function(LiveDanmuControlEvent_Closed) _then;

  /// Create a copy of LiveDanmuControlEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? field0 = null,
  }) {
    return _then(LiveDanmuControlEvent_Closed(
      null == field0
          ? _self.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
mixin _$LiveDanmuItem {
  Object get field0;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is LiveDanmuItem &&
            const DeepCollectionEquality().equals(other.field0, field0));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, const DeepCollectionEquality().hash(field0));

  @override
  String toString() {
    return 'LiveDanmuItem(field0: $field0)';
  }
}

/// @nodoc
class $LiveDanmuItemCopyWith<$Res> {
  $LiveDanmuItemCopyWith(LiveDanmuItem _, $Res Function(LiveDanmuItem) __);
}

/// Adds pattern-matching-related methods to [LiveDanmuItem].
extension LiveDanmuItemPatterns on LiveDanmuItem {
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
    TResult Function(LiveDanmuItem_Message value)? message,
    TResult Function(LiveDanmuItem_Control value)? control,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case LiveDanmuItem_Message() when message != null:
        return message(_that);
      case LiveDanmuItem_Control() when control != null:
        return control(_that);
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
    required TResult Function(LiveDanmuItem_Message value) message,
    required TResult Function(LiveDanmuItem_Control value) control,
  }) {
    final _that = this;
    switch (_that) {
      case LiveDanmuItem_Message():
        return message(_that);
      case LiveDanmuItem_Control():
        return control(_that);
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
    TResult? Function(LiveDanmuItem_Message value)? message,
    TResult? Function(LiveDanmuItem_Control value)? control,
  }) {
    final _that = this;
    switch (_that) {
      case LiveDanmuItem_Message() when message != null:
        return message(_that);
      case LiveDanmuItem_Control() when control != null:
        return control(_that);
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
    TResult Function(LiveMessage field0)? message,
    TResult Function(LiveDanmuControlEvent field0)? control,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case LiveDanmuItem_Message() when message != null:
        return message(_that.field0);
      case LiveDanmuItem_Control() when control != null:
        return control(_that.field0);
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
    required TResult Function(LiveMessage field0) message,
    required TResult Function(LiveDanmuControlEvent field0) control,
  }) {
    final _that = this;
    switch (_that) {
      case LiveDanmuItem_Message():
        return message(_that.field0);
      case LiveDanmuItem_Control():
        return control(_that.field0);
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
    TResult? Function(LiveMessage field0)? message,
    TResult? Function(LiveDanmuControlEvent field0)? control,
  }) {
    final _that = this;
    switch (_that) {
      case LiveDanmuItem_Message() when message != null:
        return message(_that.field0);
      case LiveDanmuItem_Control() when control != null:
        return control(_that.field0);
      case _:
        return null;
    }
  }
}

/// @nodoc

class LiveDanmuItem_Message extends LiveDanmuItem {
  const LiveDanmuItem_Message(this.field0) : super._();

  @override
  final LiveMessage field0;

  /// Create a copy of LiveDanmuItem
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $LiveDanmuItem_MessageCopyWith<LiveDanmuItem_Message> get copyWith =>
      _$LiveDanmuItem_MessageCopyWithImpl<LiveDanmuItem_Message>(
          this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is LiveDanmuItem_Message &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @override
  String toString() {
    return 'LiveDanmuItem.message(field0: $field0)';
  }
}

/// @nodoc
abstract mixin class $LiveDanmuItem_MessageCopyWith<$Res>
    implements $LiveDanmuItemCopyWith<$Res> {
  factory $LiveDanmuItem_MessageCopyWith(LiveDanmuItem_Message value,
          $Res Function(LiveDanmuItem_Message) _then) =
      _$LiveDanmuItem_MessageCopyWithImpl;
  @useResult
  $Res call({LiveMessage field0});
}

/// @nodoc
class _$LiveDanmuItem_MessageCopyWithImpl<$Res>
    implements $LiveDanmuItem_MessageCopyWith<$Res> {
  _$LiveDanmuItem_MessageCopyWithImpl(this._self, this._then);

  final LiveDanmuItem_Message _self;
  final $Res Function(LiveDanmuItem_Message) _then;

  /// Create a copy of LiveDanmuItem
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? field0 = null,
  }) {
    return _then(LiveDanmuItem_Message(
      null == field0
          ? _self.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as LiveMessage,
    ));
  }
}

/// @nodoc

class LiveDanmuItem_Control extends LiveDanmuItem {
  const LiveDanmuItem_Control(this.field0) : super._();

  @override
  final LiveDanmuControlEvent field0;

  /// Create a copy of LiveDanmuItem
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $LiveDanmuItem_ControlCopyWith<LiveDanmuItem_Control> get copyWith =>
      _$LiveDanmuItem_ControlCopyWithImpl<LiveDanmuItem_Control>(
          this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is LiveDanmuItem_Control &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @override
  String toString() {
    return 'LiveDanmuItem.control(field0: $field0)';
  }
}

/// @nodoc
abstract mixin class $LiveDanmuItem_ControlCopyWith<$Res>
    implements $LiveDanmuItemCopyWith<$Res> {
  factory $LiveDanmuItem_ControlCopyWith(LiveDanmuItem_Control value,
          $Res Function(LiveDanmuItem_Control) _then) =
      _$LiveDanmuItem_ControlCopyWithImpl;
  @useResult
  $Res call({LiveDanmuControlEvent field0});

  $LiveDanmuControlEventCopyWith<$Res> get field0;
}

/// @nodoc
class _$LiveDanmuItem_ControlCopyWithImpl<$Res>
    implements $LiveDanmuItem_ControlCopyWith<$Res> {
  _$LiveDanmuItem_ControlCopyWithImpl(this._self, this._then);

  final LiveDanmuItem_Control _self;
  final $Res Function(LiveDanmuItem_Control) _then;

  /// Create a copy of LiveDanmuItem
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? field0 = null,
  }) {
    return _then(LiveDanmuItem_Control(
      null == field0
          ? _self.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as LiveDanmuControlEvent,
    ));
  }

  /// Create a copy of LiveDanmuItem
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $LiveDanmuControlEventCopyWith<$Res> get field0 {
    return $LiveDanmuControlEventCopyWith<$Res>(_self.field0, (value) {
      return _then(_self.copyWith(field0: value));
    });
  }
}

// dart format on
