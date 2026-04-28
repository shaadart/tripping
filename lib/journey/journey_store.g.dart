// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'journey_store.dart';

// ignore_for_file: type=lint
class Journeys extends Table with TableInfo<Journeys, JourneyRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Journeys(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _uuidMeta = const VerificationMeta('uuid');
  late final GeneratedColumn<String> uuid = GeneratedColumn<String>(
    'uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL UNIQUE',
  );
  late final GeneratedColumnWithTypeConverter<JourneyMode, String> mode =
      GeneratedColumn<String>(
        'mode',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        $customConstraints: 'NOT NULL',
      ).withConverter<JourneyMode>(Journeys.$convertermode);
  late final GeneratedColumnWithTypeConverter<JourneyStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        $customConstraints: 'NOT NULL',
      ).withConverter<JourneyStatus>(Journeys.$converterstatus);
  late final GeneratedColumnWithTypeConverter<DateTime, int> createdAt =
      GeneratedColumn<int>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
        $customConstraints: 'NOT NULL',
      ).withConverter<DateTime>(Journeys.$convertercreatedAt);
  late final GeneratedColumnWithTypeConverter<DateTime?, int> endedAt =
      GeneratedColumn<int>(
        'ended_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        $customConstraints: '',
      ).withConverter<DateTime?>(Journeys.$converterendedAtn);
  static const VerificationMeta _summaryVersionMeta = const VerificationMeta(
    'summaryVersion',
  );
  late final GeneratedColumn<int> summaryVersion = GeneratedColumn<int>(
    'summary_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _metersMeta = const VerificationMeta('meters');
  late final GeneratedColumn<double> meters = GeneratedColumn<double>(
    'meters',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _movingMsMeta = const VerificationMeta(
    'movingMs',
  );
  late final GeneratedColumn<int> movingMs = GeneratedColumn<int>(
    'moving_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _recordedMsMeta = const VerificationMeta(
    'recordedMs',
  );
  late final GeneratedColumn<int> recordedMs = GeneratedColumn<int>(
    'recorded_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _outlineMeta = const VerificationMeta(
    'outline',
  );
  late final GeneratedColumn<String> outline = GeneratedColumn<String>(
    'outline',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    uuid,
    mode,
    status,
    createdAt,
    endedAt,
    summaryVersion,
    meters,
    movingMs,
    recordedMs,
    outline,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'journeys';
  @override
  VerificationContext validateIntegrity(
    Insertable<JourneyRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('uuid')) {
      context.handle(
        _uuidMeta,
        uuid.isAcceptableOrUnknown(data['uuid']!, _uuidMeta),
      );
    } else if (isInserting) {
      context.missing(_uuidMeta);
    }
    if (data.containsKey('summary_version')) {
      context.handle(
        _summaryVersionMeta,
        summaryVersion.isAcceptableOrUnknown(
          data['summary_version']!,
          _summaryVersionMeta,
        ),
      );
    }
    if (data.containsKey('meters')) {
      context.handle(
        _metersMeta,
        meters.isAcceptableOrUnknown(data['meters']!, _metersMeta),
      );
    }
    if (data.containsKey('moving_ms')) {
      context.handle(
        _movingMsMeta,
        movingMs.isAcceptableOrUnknown(data['moving_ms']!, _movingMsMeta),
      );
    }
    if (data.containsKey('recorded_ms')) {
      context.handle(
        _recordedMsMeta,
        recordedMs.isAcceptableOrUnknown(data['recorded_ms']!, _recordedMsMeta),
      );
    }
    if (data.containsKey('outline')) {
      context.handle(
        _outlineMeta,
        outline.isAcceptableOrUnknown(data['outline']!, _outlineMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  JourneyRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return JourneyRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      uuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uuid'],
      )!,
      mode: Journeys.$convertermode.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}mode'],
        )!,
      ),
      status: Journeys.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      createdAt: Journeys.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      endedAt: Journeys.$converterendedAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}ended_at'],
        ),
      ),
      summaryVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}summary_version'],
      ),
      meters: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}meters'],
      ),
      movingMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}moving_ms'],
      ),
      recordedMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}recorded_ms'],
      ),
      outline: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}outline'],
      ),
    );
  }

  @override
  Journeys createAlias(String alias) {
    return Journeys(attachedDatabase, alias);
  }

  static JsonTypeConverter2<JourneyMode, String, String> $convertermode =
      const EnumNameConverter<JourneyMode>(JourneyMode.values);
  static JsonTypeConverter2<JourneyStatus, String, String> $converterstatus =
      const EnumNameConverter<JourneyStatus>(JourneyStatus.values);
  static TypeConverter<DateTime, int> $convertercreatedAt = const UtcMillis();
  static TypeConverter<DateTime, int> $converterendedAt = const UtcMillis();
  static TypeConverter<DateTime?, int?> $converterendedAtn =
      NullAwareTypeConverter.wrap($converterendedAt);
  @override
  bool get dontWriteConstraints => true;
}

class JourneyRow extends DataClass implements Insertable<JourneyRow> {
  final int id;
  final String uuid;
  final JourneyMode mode;
  final JourneyStatus status;
  final DateTime createdAt;
  final DateTime? endedAt;

  /// A summary derived from the track, cached for the journey list (v2).
  /// NULL, or a summary_version older than the app's, means "derive again":
  /// the track is the truth.
  final int? summaryVersion;
  final double? meters;
  final int? movingMs;
  final int? recordedMs;

  /// JSON: per segment, a few [longitude, latitude] pairs for a thumbnail.
  final String? outline;
  const JourneyRow({
    required this.id,
    required this.uuid,
    required this.mode,
    required this.status,
    required this.createdAt,
    this.endedAt,
    this.summaryVersion,
    this.meters,
    this.movingMs,
    this.recordedMs,
    this.outline,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['uuid'] = Variable<String>(uuid);
    {
      map['mode'] = Variable<String>(Journeys.$convertermode.toSql(mode));
    }
    {
      map['status'] = Variable<String>(Journeys.$converterstatus.toSql(status));
    }
    {
      map['created_at'] = Variable<int>(
        Journeys.$convertercreatedAt.toSql(createdAt),
      );
    }
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<int>(
        Journeys.$converterendedAtn.toSql(endedAt),
      );
    }
    if (!nullToAbsent || summaryVersion != null) {
      map['summary_version'] = Variable<int>(summaryVersion);
    }
    if (!nullToAbsent || meters != null) {
      map['meters'] = Variable<double>(meters);
    }
    if (!nullToAbsent || movingMs != null) {
      map['moving_ms'] = Variable<int>(movingMs);
    }
    if (!nullToAbsent || recordedMs != null) {
      map['recorded_ms'] = Variable<int>(recordedMs);
    }
    if (!nullToAbsent || outline != null) {
      map['outline'] = Variable<String>(outline);
    }
    return map;
  }

  JourneysCompanion toCompanion(bool nullToAbsent) {
    return JourneysCompanion(
      id: Value(id),
      uuid: Value(uuid),
      mode: Value(mode),
      status: Value(status),
      createdAt: Value(createdAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      summaryVersion: summaryVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(summaryVersion),
      meters: meters == null && nullToAbsent
          ? const Value.absent()
          : Value(meters),
      movingMs: movingMs == null && nullToAbsent
          ? const Value.absent()
          : Value(movingMs),
      recordedMs: recordedMs == null && nullToAbsent
          ? const Value.absent()
          : Value(recordedMs),
      outline: outline == null && nullToAbsent
          ? const Value.absent()
          : Value(outline),
    );
  }

  factory JourneyRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return JourneyRow(
      id: serializer.fromJson<int>(json['id']),
      uuid: serializer.fromJson<String>(json['uuid']),
      mode: Journeys.$convertermode.fromJson(
        serializer.fromJson<String>(json['mode']),
      ),
      status: Journeys.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      createdAt: serializer.fromJson<DateTime>(json['created_at']),
      endedAt: serializer.fromJson<DateTime?>(json['ended_at']),
      summaryVersion: serializer.fromJson<int?>(json['summary_version']),
      meters: serializer.fromJson<double?>(json['meters']),
      movingMs: serializer.fromJson<int?>(json['moving_ms']),
      recordedMs: serializer.fromJson<int?>(json['recorded_ms']),
      outline: serializer.fromJson<String?>(json['outline']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'uuid': serializer.toJson<String>(uuid),
      'mode': serializer.toJson<String>(Journeys.$convertermode.toJson(mode)),
      'status': serializer.toJson<String>(
        Journeys.$converterstatus.toJson(status),
      ),
      'created_at': serializer.toJson<DateTime>(createdAt),
      'ended_at': serializer.toJson<DateTime?>(endedAt),
      'summary_version': serializer.toJson<int?>(summaryVersion),
      'meters': serializer.toJson<double?>(meters),
      'moving_ms': serializer.toJson<int?>(movingMs),
      'recorded_ms': serializer.toJson<int?>(recordedMs),
      'outline': serializer.toJson<String?>(outline),
    };
  }

  JourneyRow copyWith({
    int? id,
    String? uuid,
    JourneyMode? mode,
    JourneyStatus? status,
    DateTime? createdAt,
    Value<DateTime?> endedAt = const Value.absent(),
    Value<int?> summaryVersion = const Value.absent(),
    Value<double?> meters = const Value.absent(),
    Value<int?> movingMs = const Value.absent(),
    Value<int?> recordedMs = const Value.absent(),
    Value<String?> outline = const Value.absent(),
  }) => JourneyRow(
    id: id ?? this.id,
    uuid: uuid ?? this.uuid,
    mode: mode ?? this.mode,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    endedAt: endedAt.present ? endedAt.value : this.endedAt,
    summaryVersion: summaryVersion.present
        ? summaryVersion.value
        : this.summaryVersion,
    meters: meters.present ? meters.value : this.meters,
    movingMs: movingMs.present ? movingMs.value : this.movingMs,
    recordedMs: recordedMs.present ? recordedMs.value : this.recordedMs,
    outline: outline.present ? outline.value : this.outline,
  );
  JourneyRow copyWithCompanion(JourneysCompanion data) {
    return JourneyRow(
      id: data.id.present ? data.id.value : this.id,
      uuid: data.uuid.present ? data.uuid.value : this.uuid,
      mode: data.mode.present ? data.mode.value : this.mode,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      summaryVersion: data.summaryVersion.present
          ? data.summaryVersion.value
          : this.summaryVersion,
      meters: data.meters.present ? data.meters.value : this.meters,
      movingMs: data.movingMs.present ? data.movingMs.value : this.movingMs,
      recordedMs: data.recordedMs.present
          ? data.recordedMs.value
          : this.recordedMs,
      outline: data.outline.present ? data.outline.value : this.outline,
    );
  }

  @override
  String toString() {
    return (StringBuffer('JourneyRow(')
          ..write('id: $id, ')
          ..write('uuid: $uuid, ')
          ..write('mode: $mode, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('summaryVersion: $summaryVersion, ')
          ..write('meters: $meters, ')
          ..write('movingMs: $movingMs, ')
          ..write('recordedMs: $recordedMs, ')
          ..write('outline: $outline')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    uuid,
    mode,
    status,
    createdAt,
    endedAt,
    summaryVersion,
    meters,
    movingMs,
    recordedMs,
    outline,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JourneyRow &&
          other.id == this.id &&
          other.uuid == this.uuid &&
          other.mode == this.mode &&
          other.status == this.status &&
          other.createdAt == this.createdAt &&
          other.endedAt == this.endedAt &&
          other.summaryVersion == this.summaryVersion &&
          other.meters == this.meters &&
          other.movingMs == this.movingMs &&
          other.recordedMs == this.recordedMs &&
          other.outline == this.outline);
}

class JourneysCompanion extends UpdateCompanion<JourneyRow> {
  final Value<int> id;
  final Value<String> uuid;
  final Value<JourneyMode> mode;
  final Value<JourneyStatus> status;
  final Value<DateTime> createdAt;
  final Value<DateTime?> endedAt;
  final Value<int?> summaryVersion;
  final Value<double?> meters;
  final Value<int?> movingMs;
  final Value<int?> recordedMs;
  final Value<String?> outline;
  const JourneysCompanion({
    this.id = const Value.absent(),
    this.uuid = const Value.absent(),
    this.mode = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.summaryVersion = const Value.absent(),
    this.meters = const Value.absent(),
    this.movingMs = const Value.absent(),
    this.recordedMs = const Value.absent(),
    this.outline = const Value.absent(),
  });
  JourneysCompanion.insert({
    this.id = const Value.absent(),
    required String uuid,
    required JourneyMode mode,
    required JourneyStatus status,
    required DateTime createdAt,
    this.endedAt = const Value.absent(),
    this.summaryVersion = const Value.absent(),
    this.meters = const Value.absent(),
    this.movingMs = const Value.absent(),
    this.recordedMs = const Value.absent(),
    this.outline = const Value.absent(),
  }) : uuid = Value(uuid),
       mode = Value(mode),
       status = Value(status),
       createdAt = Value(createdAt);
  static Insertable<JourneyRow> custom({
    Expression<int>? id,
    Expression<String>? uuid,
    Expression<String>? mode,
    Expression<String>? status,
    Expression<int>? createdAt,
    Expression<int>? endedAt,
    Expression<int>? summaryVersion,
    Expression<double>? meters,
    Expression<int>? movingMs,
    Expression<int>? recordedMs,
    Expression<String>? outline,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (uuid != null) 'uuid': uuid,
      if (mode != null) 'mode': mode,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (summaryVersion != null) 'summary_version': summaryVersion,
      if (meters != null) 'meters': meters,
      if (movingMs != null) 'moving_ms': movingMs,
      if (recordedMs != null) 'recorded_ms': recordedMs,
      if (outline != null) 'outline': outline,
    });
  }

  JourneysCompanion copyWith({
    Value<int>? id,
    Value<String>? uuid,
    Value<JourneyMode>? mode,
    Value<JourneyStatus>? status,
    Value<DateTime>? createdAt,
    Value<DateTime?>? endedAt,
    Value<int?>? summaryVersion,
    Value<double?>? meters,
    Value<int?>? movingMs,
    Value<int?>? recordedMs,
    Value<String?>? outline,
  }) {
    return JourneysCompanion(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      mode: mode ?? this.mode,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      endedAt: endedAt ?? this.endedAt,
      summaryVersion: summaryVersion ?? this.summaryVersion,
      meters: meters ?? this.meters,
      movingMs: movingMs ?? this.movingMs,
      recordedMs: recordedMs ?? this.recordedMs,
      outline: outline ?? this.outline,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (uuid.present) {
      map['uuid'] = Variable<String>(uuid.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(Journeys.$convertermode.toSql(mode.value));
    }
    if (status.present) {
      map['status'] = Variable<String>(
        Journeys.$converterstatus.toSql(status.value),
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(
        Journeys.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<int>(
        Journeys.$converterendedAtn.toSql(endedAt.value),
      );
    }
    if (summaryVersion.present) {
      map['summary_version'] = Variable<int>(summaryVersion.value);
    }
    if (meters.present) {
      map['meters'] = Variable<double>(meters.value);
    }
    if (movingMs.present) {
      map['moving_ms'] = Variable<int>(movingMs.value);
    }
    if (recordedMs.present) {
      map['recorded_ms'] = Variable<int>(recordedMs.value);
    }
    if (outline.present) {
      map['outline'] = Variable<String>(outline.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('JourneysCompanion(')
          ..write('id: $id, ')
          ..write('uuid: $uuid, ')
          ..write('mode: $mode, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('summaryVersion: $summaryVersion, ')
          ..write('meters: $meters, ')
          ..write('movingMs: $movingMs, ')
          ..write('recordedMs: $recordedMs, ')
          ..write('outline: $outline')
          ..write(')'))
        .toString();
  }
}

class Segments extends Table with TableInfo<Segments, SegmentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Segments(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _journeyIdMeta = const VerificationMeta(
    'journeyId',
  );
  late final GeneratedColumn<int> journeyId = GeneratedColumn<int>(
    'journey_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES journeys(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  late final GeneratedColumnWithTypeConverter<DateTime, int> startedAt =
      GeneratedColumn<int>(
        'started_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
        $customConstraints: 'NOT NULL',
      ).withConverter<DateTime>(Segments.$converterstartedAt);
  late final GeneratedColumnWithTypeConverter<DateTime?, int> endedAt =
      GeneratedColumn<int>(
        'ended_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        $customConstraints: '',
      ).withConverter<DateTime?>(Segments.$converterendedAtn);
  late final GeneratedColumnWithTypeConverter<SegmentEnd?, String> endReason =
      GeneratedColumn<String>(
        'end_reason',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        $customConstraints: '',
      ).withConverter<SegmentEnd?>(Segments.$converterendReasonn);
  @override
  List<GeneratedColumn> get $columns => [
    journeyId,
    seq,
    startedAt,
    endedAt,
    endReason,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'segments';
  @override
  VerificationContext validateIntegrity(
    Insertable<SegmentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('journey_id')) {
      context.handle(
        _journeyIdMeta,
        journeyId.isAcceptableOrUnknown(data['journey_id']!, _journeyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_journeyIdMeta);
    }
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    } else if (isInserting) {
      context.missing(_seqMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {journeyId, seq};
  @override
  SegmentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SegmentRow(
      journeyId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}journey_id'],
      )!,
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      )!,
      startedAt: Segments.$converterstartedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}started_at'],
        )!,
      ),
      endedAt: Segments.$converterendedAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}ended_at'],
        ),
      ),
      endReason: Segments.$converterendReasonn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}end_reason'],
        ),
      ),
    );
  }

  @override
  Segments createAlias(String alias) {
    return Segments(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterstartedAt = const UtcMillis();
  static TypeConverter<DateTime, int> $converterendedAt = const UtcMillis();
  static TypeConverter<DateTime?, int?> $converterendedAtn =
      NullAwareTypeConverter.wrap($converterendedAt);
  static JsonTypeConverter2<SegmentEnd, String, String> $converterendReason =
      const EnumNameConverter<SegmentEnd>(SegmentEnd.values);
  static JsonTypeConverter2<SegmentEnd?, String?, String?>
  $converterendReasonn = JsonTypeConverter2.asNullable($converterendReason);
  @override
  List<String> get customConstraints => const ['PRIMARY KEY(journey_id, seq)'];
  @override
  bool get dontWriteConstraints => true;
}

class SegmentRow extends DataClass implements Insertable<SegmentRow> {
  final int journeyId;
  final int seq;
  final DateTime startedAt;
  final DateTime? endedAt;
  final SegmentEnd? endReason;
  const SegmentRow({
    required this.journeyId,
    required this.seq,
    required this.startedAt,
    this.endedAt,
    this.endReason,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['journey_id'] = Variable<int>(journeyId);
    map['seq'] = Variable<int>(seq);
    {
      map['started_at'] = Variable<int>(
        Segments.$converterstartedAt.toSql(startedAt),
      );
    }
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<int>(
        Segments.$converterendedAtn.toSql(endedAt),
      );
    }
    if (!nullToAbsent || endReason != null) {
      map['end_reason'] = Variable<String>(
        Segments.$converterendReasonn.toSql(endReason),
      );
    }
    return map;
  }

  SegmentsCompanion toCompanion(bool nullToAbsent) {
    return SegmentsCompanion(
      journeyId: Value(journeyId),
      seq: Value(seq),
      startedAt: Value(startedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      endReason: endReason == null && nullToAbsent
          ? const Value.absent()
          : Value(endReason),
    );
  }

  factory SegmentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SegmentRow(
      journeyId: serializer.fromJson<int>(json['journey_id']),
      seq: serializer.fromJson<int>(json['seq']),
      startedAt: serializer.fromJson<DateTime>(json['started_at']),
      endedAt: serializer.fromJson<DateTime?>(json['ended_at']),
      endReason: Segments.$converterendReasonn.fromJson(
        serializer.fromJson<String?>(json['end_reason']),
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'journey_id': serializer.toJson<int>(journeyId),
      'seq': serializer.toJson<int>(seq),
      'started_at': serializer.toJson<DateTime>(startedAt),
      'ended_at': serializer.toJson<DateTime?>(endedAt),
      'end_reason': serializer.toJson<String?>(
        Segments.$converterendReasonn.toJson(endReason),
      ),
    };
  }

  SegmentRow copyWith({
    int? journeyId,
    int? seq,
    DateTime? startedAt,
    Value<DateTime?> endedAt = const Value.absent(),
    Value<SegmentEnd?> endReason = const Value.absent(),
  }) => SegmentRow(
    journeyId: journeyId ?? this.journeyId,
    seq: seq ?? this.seq,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt.present ? endedAt.value : this.endedAt,
    endReason: endReason.present ? endReason.value : this.endReason,
  );
  SegmentRow copyWithCompanion(SegmentsCompanion data) {
    return SegmentRow(
      journeyId: data.journeyId.present ? data.journeyId.value : this.journeyId,
      seq: data.seq.present ? data.seq.value : this.seq,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      endReason: data.endReason.present ? data.endReason.value : this.endReason,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SegmentRow(')
          ..write('journeyId: $journeyId, ')
          ..write('seq: $seq, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('endReason: $endReason')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(journeyId, seq, startedAt, endedAt, endReason);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SegmentRow &&
          other.journeyId == this.journeyId &&
          other.seq == this.seq &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.endReason == this.endReason);
}

class SegmentsCompanion extends UpdateCompanion<SegmentRow> {
  final Value<int> journeyId;
  final Value<int> seq;
  final Value<DateTime> startedAt;
  final Value<DateTime?> endedAt;
  final Value<SegmentEnd?> endReason;
  final Value<int> rowid;
  const SegmentsCompanion({
    this.journeyId = const Value.absent(),
    this.seq = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.endReason = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SegmentsCompanion.insert({
    required int journeyId,
    required int seq,
    required DateTime startedAt,
    this.endedAt = const Value.absent(),
    this.endReason = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : journeyId = Value(journeyId),
       seq = Value(seq),
       startedAt = Value(startedAt);
  static Insertable<SegmentRow> custom({
    Expression<int>? journeyId,
    Expression<int>? seq,
    Expression<int>? startedAt,
    Expression<int>? endedAt,
    Expression<String>? endReason,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (journeyId != null) 'journey_id': journeyId,
      if (seq != null) 'seq': seq,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (endReason != null) 'end_reason': endReason,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SegmentsCompanion copyWith({
    Value<int>? journeyId,
    Value<int>? seq,
    Value<DateTime>? startedAt,
    Value<DateTime?>? endedAt,
    Value<SegmentEnd?>? endReason,
    Value<int>? rowid,
  }) {
    return SegmentsCompanion(
      journeyId: journeyId ?? this.journeyId,
      seq: seq ?? this.seq,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      endReason: endReason ?? this.endReason,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (journeyId.present) {
      map['journey_id'] = Variable<int>(journeyId.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<int>(
        Segments.$converterstartedAt.toSql(startedAt.value),
      );
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<int>(
        Segments.$converterendedAtn.toSql(endedAt.value),
      );
    }
    if (endReason.present) {
      map['end_reason'] = Variable<String>(
        Segments.$converterendReasonn.toSql(endReason.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SegmentsCompanion(')
          ..write('journeyId: $journeyId, ')
          ..write('seq: $seq, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('endReason: $endReason, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class TrackPoints extends Table with TableInfo<TrackPoints, TrackPointRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  TrackPoints(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _journeyIdMeta = const VerificationMeta(
    'journeyId',
  );
  late final GeneratedColumn<int> journeyId = GeneratedColumn<int>(
    'journey_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES journeys(id)ON DELETE CASCADE',
  );
  late final GeneratedColumnWithTypeConverter<DateTime, int> time =
      GeneratedColumn<int>(
        'time',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
        $customConstraints: 'NOT NULL',
      ).withConverter<DateTime>(TrackPoints.$convertertime);
  static const VerificationMeta _segmentMeta = const VerificationMeta(
    'segment',
  );
  late final GeneratedColumn<int> segment = GeneratedColumn<int>(
    'segment',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _accuracyMeta = const VerificationMeta(
    'accuracy',
  );
  late final GeneratedColumn<double> accuracy = GeneratedColumn<double>(
    'accuracy',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _altitudeMeta = const VerificationMeta(
    'altitude',
  );
  late final GeneratedColumn<double> altitude = GeneratedColumn<double>(
    'altitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _altitudeAccuracyMeta = const VerificationMeta(
    'altitudeAccuracy',
  );
  late final GeneratedColumn<double> altitudeAccuracy = GeneratedColumn<double>(
    'altitude_accuracy',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _speedMeta = const VerificationMeta('speed');
  late final GeneratedColumn<double> speed = GeneratedColumn<double>(
    'speed',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _headingMeta = const VerificationMeta(
    'heading',
  );
  late final GeneratedColumn<double> heading = GeneratedColumn<double>(
    'heading',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [
    journeyId,
    time,
    segment,
    latitude,
    longitude,
    accuracy,
    altitude,
    altitudeAccuracy,
    speed,
    heading,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'track_points';
  @override
  VerificationContext validateIntegrity(
    Insertable<TrackPointRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('journey_id')) {
      context.handle(
        _journeyIdMeta,
        journeyId.isAcceptableOrUnknown(data['journey_id']!, _journeyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_journeyIdMeta);
    }
    if (data.containsKey('segment')) {
      context.handle(
        _segmentMeta,
        segment.isAcceptableOrUnknown(data['segment']!, _segmentMeta),
      );
    } else if (isInserting) {
      context.missing(_segmentMeta);
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('accuracy')) {
      context.handle(
        _accuracyMeta,
        accuracy.isAcceptableOrUnknown(data['accuracy']!, _accuracyMeta),
      );
    }
    if (data.containsKey('altitude')) {
      context.handle(
        _altitudeMeta,
        altitude.isAcceptableOrUnknown(data['altitude']!, _altitudeMeta),
      );
    }
    if (data.containsKey('altitude_accuracy')) {
      context.handle(
        _altitudeAccuracyMeta,
        altitudeAccuracy.isAcceptableOrUnknown(
          data['altitude_accuracy']!,
          _altitudeAccuracyMeta,
        ),
      );
    }
    if (data.containsKey('speed')) {
      context.handle(
        _speedMeta,
        speed.isAcceptableOrUnknown(data['speed']!, _speedMeta),
      );
    }
    if (data.containsKey('heading')) {
      context.handle(
        _headingMeta,
        heading.isAcceptableOrUnknown(data['heading']!, _headingMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {journeyId, time};
  @override
  TrackPointRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrackPointRow(
      journeyId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}journey_id'],
      )!,
      time: TrackPoints.$convertertime.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}time'],
        )!,
      ),
      segment: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}segment'],
      )!,
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      )!,
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      )!,
      accuracy: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}accuracy'],
      ),
      altitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}altitude'],
      ),
      altitudeAccuracy: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}altitude_accuracy'],
      ),
      speed: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}speed'],
      ),
      heading: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}heading'],
      ),
    );
  }

  @override
  TrackPoints createAlias(String alias) {
    return TrackPoints(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $convertertime = const UtcMillis();
  @override
  bool get withoutRowId => true;
  @override
  List<String> get customConstraints => const ['PRIMARY KEY(journey_id, time)'];
  @override
  bool get dontWriteConstraints => true;
}

class TrackPointRow extends DataClass implements Insertable<TrackPointRow> {
  final int journeyId;
  final DateTime time;
  final int segment;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? altitude;
  final double? altitudeAccuracy;
  final double? speed;
  final double? heading;
  const TrackPointRow({
    required this.journeyId,
    required this.time,
    required this.segment,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.altitude,
    this.altitudeAccuracy,
    this.speed,
    this.heading,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['journey_id'] = Variable<int>(journeyId);
    {
      map['time'] = Variable<int>(TrackPoints.$convertertime.toSql(time));
    }
    map['segment'] = Variable<int>(segment);
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    if (!nullToAbsent || accuracy != null) {
      map['accuracy'] = Variable<double>(accuracy);
    }
    if (!nullToAbsent || altitude != null) {
      map['altitude'] = Variable<double>(altitude);
    }
    if (!nullToAbsent || altitudeAccuracy != null) {
      map['altitude_accuracy'] = Variable<double>(altitudeAccuracy);
    }
    if (!nullToAbsent || speed != null) {
      map['speed'] = Variable<double>(speed);
    }
    if (!nullToAbsent || heading != null) {
      map['heading'] = Variable<double>(heading);
    }
    return map;
  }

  TrackPointsCompanion toCompanion(bool nullToAbsent) {
    return TrackPointsCompanion(
      journeyId: Value(journeyId),
      time: Value(time),
      segment: Value(segment),
      latitude: Value(latitude),
      longitude: Value(longitude),
      accuracy: accuracy == null && nullToAbsent
          ? const Value.absent()
          : Value(accuracy),
      altitude: altitude == null && nullToAbsent
          ? const Value.absent()
          : Value(altitude),
      altitudeAccuracy: altitudeAccuracy == null && nullToAbsent
          ? const Value.absent()
          : Value(altitudeAccuracy),
      speed: speed == null && nullToAbsent
          ? const Value.absent()
          : Value(speed),
      heading: heading == null && nullToAbsent
          ? const Value.absent()
          : Value(heading),
    );
  }

  factory TrackPointRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrackPointRow(
      journeyId: serializer.fromJson<int>(json['journey_id']),
      time: serializer.fromJson<DateTime>(json['time']),
      segment: serializer.fromJson<int>(json['segment']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      accuracy: serializer.fromJson<double?>(json['accuracy']),
      altitude: serializer.fromJson<double?>(json['altitude']),
      altitudeAccuracy: serializer.fromJson<double?>(json['altitude_accuracy']),
      speed: serializer.fromJson<double?>(json['speed']),
      heading: serializer.fromJson<double?>(json['heading']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'journey_id': serializer.toJson<int>(journeyId),
      'time': serializer.toJson<DateTime>(time),
      'segment': serializer.toJson<int>(segment),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'accuracy': serializer.toJson<double?>(accuracy),
      'altitude': serializer.toJson<double?>(altitude),
      'altitude_accuracy': serializer.toJson<double?>(altitudeAccuracy),
      'speed': serializer.toJson<double?>(speed),
      'heading': serializer.toJson<double?>(heading),
    };
  }

  TrackPointRow copyWith({
    int? journeyId,
    DateTime? time,
    int? segment,
    double? latitude,
    double? longitude,
    Value<double?> accuracy = const Value.absent(),
    Value<double?> altitude = const Value.absent(),
    Value<double?> altitudeAccuracy = const Value.absent(),
    Value<double?> speed = const Value.absent(),
    Value<double?> heading = const Value.absent(),
  }) => TrackPointRow(
    journeyId: journeyId ?? this.journeyId,
    time: time ?? this.time,
    segment: segment ?? this.segment,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    accuracy: accuracy.present ? accuracy.value : this.accuracy,
    altitude: altitude.present ? altitude.value : this.altitude,
    altitudeAccuracy: altitudeAccuracy.present
        ? altitudeAccuracy.value
        : this.altitudeAccuracy,
    speed: speed.present ? speed.value : this.speed,
    heading: heading.present ? heading.value : this.heading,
  );
  TrackPointRow copyWithCompanion(TrackPointsCompanion data) {
    return TrackPointRow(
      journeyId: data.journeyId.present ? data.journeyId.value : this.journeyId,
      time: data.time.present ? data.time.value : this.time,
      segment: data.segment.present ? data.segment.value : this.segment,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      accuracy: data.accuracy.present ? data.accuracy.value : this.accuracy,
      altitude: data.altitude.present ? data.altitude.value : this.altitude,
      altitudeAccuracy: data.altitudeAccuracy.present
          ? data.altitudeAccuracy.value
          : this.altitudeAccuracy,
      speed: data.speed.present ? data.speed.value : this.speed,
      heading: data.heading.present ? data.heading.value : this.heading,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrackPointRow(')
          ..write('journeyId: $journeyId, ')
          ..write('time: $time, ')
          ..write('segment: $segment, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('accuracy: $accuracy, ')
          ..write('altitude: $altitude, ')
          ..write('altitudeAccuracy: $altitudeAccuracy, ')
          ..write('speed: $speed, ')
          ..write('heading: $heading')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    journeyId,
    time,
    segment,
    latitude,
    longitude,
    accuracy,
    altitude,
    altitudeAccuracy,
    speed,
    heading,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrackPointRow &&
          other.journeyId == this.journeyId &&
          other.time == this.time &&
          other.segment == this.segment &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.accuracy == this.accuracy &&
          other.altitude == this.altitude &&
          other.altitudeAccuracy == this.altitudeAccuracy &&
          other.speed == this.speed &&
          other.heading == this.heading);
}

class TrackPointsCompanion extends UpdateCompanion<TrackPointRow> {
  final Value<int> journeyId;
  final Value<DateTime> time;
  final Value<int> segment;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<double?> accuracy;
  final Value<double?> altitude;
  final Value<double?> altitudeAccuracy;
  final Value<double?> speed;
  final Value<double?> heading;
  const TrackPointsCompanion({
    this.journeyId = const Value.absent(),
    this.time = const Value.absent(),
    this.segment = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.accuracy = const Value.absent(),
    this.altitude = const Value.absent(),
    this.altitudeAccuracy = const Value.absent(),
    this.speed = const Value.absent(),
    this.heading = const Value.absent(),
  });
  TrackPointsCompanion.insert({
    required int journeyId,
    required DateTime time,
    required int segment,
    required double latitude,
    required double longitude,
    this.accuracy = const Value.absent(),
    this.altitude = const Value.absent(),
    this.altitudeAccuracy = const Value.absent(),
    this.speed = const Value.absent(),
    this.heading = const Value.absent(),
  }) : journeyId = Value(journeyId),
       time = Value(time),
       segment = Value(segment),
       latitude = Value(latitude),
       longitude = Value(longitude);
  static Insertable<TrackPointRow> custom({
    Expression<int>? journeyId,
    Expression<int>? time,
    Expression<int>? segment,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<double>? accuracy,
    Expression<double>? altitude,
    Expression<double>? altitudeAccuracy,
    Expression<double>? speed,
    Expression<double>? heading,
  }) {
    return RawValuesInsertable({
      if (journeyId != null) 'journey_id': journeyId,
      if (time != null) 'time': time,
      if (segment != null) 'segment': segment,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (accuracy != null) 'accuracy': accuracy,
      if (altitude != null) 'altitude': altitude,
      if (altitudeAccuracy != null) 'altitude_accuracy': altitudeAccuracy,
      if (speed != null) 'speed': speed,
      if (heading != null) 'heading': heading,
    });
  }

  TrackPointsCompanion copyWith({
    Value<int>? journeyId,
    Value<DateTime>? time,
    Value<int>? segment,
    Value<double>? latitude,
    Value<double>? longitude,
    Value<double?>? accuracy,
    Value<double?>? altitude,
    Value<double?>? altitudeAccuracy,
    Value<double?>? speed,
    Value<double?>? heading,
  }) {
    return TrackPointsCompanion(
      journeyId: journeyId ?? this.journeyId,
      time: time ?? this.time,
      segment: segment ?? this.segment,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      altitude: altitude ?? this.altitude,
      altitudeAccuracy: altitudeAccuracy ?? this.altitudeAccuracy,
      speed: speed ?? this.speed,
      heading: heading ?? this.heading,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (journeyId.present) {
      map['journey_id'] = Variable<int>(journeyId.value);
    }
    if (time.present) {
      map['time'] = Variable<int>(TrackPoints.$convertertime.toSql(time.value));
    }
    if (segment.present) {
      map['segment'] = Variable<int>(segment.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (accuracy.present) {
      map['accuracy'] = Variable<double>(accuracy.value);
    }
    if (altitude.present) {
      map['altitude'] = Variable<double>(altitude.value);
    }
    if (altitudeAccuracy.present) {
      map['altitude_accuracy'] = Variable<double>(altitudeAccuracy.value);
    }
    if (speed.present) {
      map['speed'] = Variable<double>(speed.value);
    }
    if (heading.present) {
      map['heading'] = Variable<double>(heading.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TrackPointsCompanion(')
          ..write('journeyId: $journeyId, ')
          ..write('time: $time, ')
          ..write('segment: $segment, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('accuracy: $accuracy, ')
          ..write('altitude: $altitude, ')
          ..write('altitudeAccuracy: $altitudeAccuracy, ')
          ..write('speed: $speed, ')
          ..write('heading: $heading')
          ..write(')'))
        .toString();
  }
}

class Waypoints extends Table with TableInfo<Waypoints, WaypointRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Waypoints(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _journeyIdMeta = const VerificationMeta(
    'journeyId',
  );
  late final GeneratedColumn<int> journeyId = GeneratedColumn<int>(
    'journey_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES journeys(id)ON DELETE CASCADE',
  );
  late final GeneratedColumnWithTypeConverter<WaypointKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        $customConstraints: 'NOT NULL',
      ).withConverter<WaypointKind>(Waypoints.$converterkind);
  late final GeneratedColumnWithTypeConverter<DateTime, int> createdAt =
      GeneratedColumn<int>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
        $customConstraints: 'NOT NULL',
      ).withConverter<DateTime>(Waypoints.$convertercreatedAt);
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _accuracyMeta = const VerificationMeta(
    'accuracy',
  );
  late final GeneratedColumn<double> accuracy = GeneratedColumn<double>(
    'accuracy',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _altitudeMeta = const VerificationMeta(
    'altitude',
  );
  late final GeneratedColumn<double> altitude = GeneratedColumn<double>(
    'altitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  late final GeneratedColumnWithTypeConverter<DateTime?, int> fixTime =
      GeneratedColumn<int>(
        'fix_time',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        $customConstraints: '',
      ).withConverter<DateTime?>(Waypoints.$converterfixTimen);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    journeyId,
    kind,
    createdAt,
    latitude,
    longitude,
    accuracy,
    altitude,
    fixTime,
    name,
    note,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'waypoints';
  @override
  VerificationContext validateIntegrity(
    Insertable<WaypointRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('journey_id')) {
      context.handle(
        _journeyIdMeta,
        journeyId.isAcceptableOrUnknown(data['journey_id']!, _journeyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_journeyIdMeta);
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('accuracy')) {
      context.handle(
        _accuracyMeta,
        accuracy.isAcceptableOrUnknown(data['accuracy']!, _accuracyMeta),
      );
    }
    if (data.containsKey('altitude')) {
      context.handle(
        _altitudeMeta,
        altitude.isAcceptableOrUnknown(data['altitude']!, _altitudeMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WaypointRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WaypointRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      journeyId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}journey_id'],
      )!,
      kind: Waypoints.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      createdAt: Waypoints.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      )!,
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      )!,
      accuracy: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}accuracy'],
      ),
      altitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}altitude'],
      ),
      fixTime: Waypoints.$converterfixTimen.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}fix_time'],
        ),
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
    );
  }

  @override
  Waypoints createAlias(String alias) {
    return Waypoints(attachedDatabase, alias);
  }

  static JsonTypeConverter2<WaypointKind, String, String> $converterkind =
      const WaypointKindByName();
  static TypeConverter<DateTime, int> $convertercreatedAt = const UtcMillis();
  static TypeConverter<DateTime, int> $converterfixTime = const UtcMillis();
  static TypeConverter<DateTime?, int?> $converterfixTimen =
      NullAwareTypeConverter.wrap($converterfixTime);
  @override
  bool get dontWriteConstraints => true;
}

class WaypointRow extends DataClass implements Insertable<WaypointRow> {
  final int id;
  final int journeyId;

  /// Stored by name. Not ENUMNAME(WaypointKind): "WaypointKind" contains
  /// "INT", which gives the column integer affinity, and the enum would be
  /// stored by its index.
  final WaypointKind kind;
  final DateTime createdAt;
  final double latitude;
  final double longitude;

  /// Marked waypoints only: the fix's accuracy, altitude and GPS time.
  final double? accuracy;
  final double? altitude;
  final DateTime? fixTime;
  final String? name;
  final String? note;
  const WaypointRow({
    required this.id,
    required this.journeyId,
    required this.kind,
    required this.createdAt,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.altitude,
    this.fixTime,
    this.name,
    this.note,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['journey_id'] = Variable<int>(journeyId);
    {
      map['kind'] = Variable<String>(Waypoints.$converterkind.toSql(kind));
    }
    {
      map['created_at'] = Variable<int>(
        Waypoints.$convertercreatedAt.toSql(createdAt),
      );
    }
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    if (!nullToAbsent || accuracy != null) {
      map['accuracy'] = Variable<double>(accuracy);
    }
    if (!nullToAbsent || altitude != null) {
      map['altitude'] = Variable<double>(altitude);
    }
    if (!nullToAbsent || fixTime != null) {
      map['fix_time'] = Variable<int>(
        Waypoints.$converterfixTimen.toSql(fixTime),
      );
    }
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    return map;
  }

  WaypointsCompanion toCompanion(bool nullToAbsent) {
    return WaypointsCompanion(
      id: Value(id),
      journeyId: Value(journeyId),
      kind: Value(kind),
      createdAt: Value(createdAt),
      latitude: Value(latitude),
      longitude: Value(longitude),
      accuracy: accuracy == null && nullToAbsent
          ? const Value.absent()
          : Value(accuracy),
      altitude: altitude == null && nullToAbsent
          ? const Value.absent()
          : Value(altitude),
      fixTime: fixTime == null && nullToAbsent
          ? const Value.absent()
          : Value(fixTime),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
    );
  }

  factory WaypointRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WaypointRow(
      id: serializer.fromJson<int>(json['id']),
      journeyId: serializer.fromJson<int>(json['journey_id']),
      kind: Waypoints.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      createdAt: serializer.fromJson<DateTime>(json['created_at']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      accuracy: serializer.fromJson<double?>(json['accuracy']),
      altitude: serializer.fromJson<double?>(json['altitude']),
      fixTime: serializer.fromJson<DateTime?>(json['fix_time']),
      name: serializer.fromJson<String?>(json['name']),
      note: serializer.fromJson<String?>(json['note']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'journey_id': serializer.toJson<int>(journeyId),
      'kind': serializer.toJson<String>(Waypoints.$converterkind.toJson(kind)),
      'created_at': serializer.toJson<DateTime>(createdAt),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'accuracy': serializer.toJson<double?>(accuracy),
      'altitude': serializer.toJson<double?>(altitude),
      'fix_time': serializer.toJson<DateTime?>(fixTime),
      'name': serializer.toJson<String?>(name),
      'note': serializer.toJson<String?>(note),
    };
  }

  WaypointRow copyWith({
    int? id,
    int? journeyId,
    WaypointKind? kind,
    DateTime? createdAt,
    double? latitude,
    double? longitude,
    Value<double?> accuracy = const Value.absent(),
    Value<double?> altitude = const Value.absent(),
    Value<DateTime?> fixTime = const Value.absent(),
    Value<String?> name = const Value.absent(),
    Value<String?> note = const Value.absent(),
  }) => WaypointRow(
    id: id ?? this.id,
    journeyId: journeyId ?? this.journeyId,
    kind: kind ?? this.kind,
    createdAt: createdAt ?? this.createdAt,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    accuracy: accuracy.present ? accuracy.value : this.accuracy,
    altitude: altitude.present ? altitude.value : this.altitude,
    fixTime: fixTime.present ? fixTime.value : this.fixTime,
    name: name.present ? name.value : this.name,
    note: note.present ? note.value : this.note,
  );
  WaypointRow copyWithCompanion(WaypointsCompanion data) {
    return WaypointRow(
      id: data.id.present ? data.id.value : this.id,
      journeyId: data.journeyId.present ? data.journeyId.value : this.journeyId,
      kind: data.kind.present ? data.kind.value : this.kind,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      accuracy: data.accuracy.present ? data.accuracy.value : this.accuracy,
      altitude: data.altitude.present ? data.altitude.value : this.altitude,
      fixTime: data.fixTime.present ? data.fixTime.value : this.fixTime,
      name: data.name.present ? data.name.value : this.name,
      note: data.note.present ? data.note.value : this.note,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WaypointRow(')
          ..write('id: $id, ')
          ..write('journeyId: $journeyId, ')
          ..write('kind: $kind, ')
          ..write('createdAt: $createdAt, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('accuracy: $accuracy, ')
          ..write('altitude: $altitude, ')
          ..write('fixTime: $fixTime, ')
          ..write('name: $name, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    journeyId,
    kind,
    createdAt,
    latitude,
    longitude,
    accuracy,
    altitude,
    fixTime,
    name,
    note,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WaypointRow &&
          other.id == this.id &&
          other.journeyId == this.journeyId &&
          other.kind == this.kind &&
          other.createdAt == this.createdAt &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.accuracy == this.accuracy &&
          other.altitude == this.altitude &&
          other.fixTime == this.fixTime &&
          other.name == this.name &&
          other.note == this.note);
}

class WaypointsCompanion extends UpdateCompanion<WaypointRow> {
  final Value<int> id;
  final Value<int> journeyId;
  final Value<WaypointKind> kind;
  final Value<DateTime> createdAt;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<double?> accuracy;
  final Value<double?> altitude;
  final Value<DateTime?> fixTime;
  final Value<String?> name;
  final Value<String?> note;
  const WaypointsCompanion({
    this.id = const Value.absent(),
    this.journeyId = const Value.absent(),
    this.kind = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.accuracy = const Value.absent(),
    this.altitude = const Value.absent(),
    this.fixTime = const Value.absent(),
    this.name = const Value.absent(),
    this.note = const Value.absent(),
  });
  WaypointsCompanion.insert({
    this.id = const Value.absent(),
    required int journeyId,
    required WaypointKind kind,
    required DateTime createdAt,
    required double latitude,
    required double longitude,
    this.accuracy = const Value.absent(),
    this.altitude = const Value.absent(),
    this.fixTime = const Value.absent(),
    this.name = const Value.absent(),
    this.note = const Value.absent(),
  }) : journeyId = Value(journeyId),
       kind = Value(kind),
       createdAt = Value(createdAt),
       latitude = Value(latitude),
       longitude = Value(longitude);
  static Insertable<WaypointRow> custom({
    Expression<int>? id,
    Expression<int>? journeyId,
    Expression<String>? kind,
    Expression<int>? createdAt,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<double>? accuracy,
    Expression<double>? altitude,
    Expression<int>? fixTime,
    Expression<String>? name,
    Expression<String>? note,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (journeyId != null) 'journey_id': journeyId,
      if (kind != null) 'kind': kind,
      if (createdAt != null) 'created_at': createdAt,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (accuracy != null) 'accuracy': accuracy,
      if (altitude != null) 'altitude': altitude,
      if (fixTime != null) 'fix_time': fixTime,
      if (name != null) 'name': name,
      if (note != null) 'note': note,
    });
  }

  WaypointsCompanion copyWith({
    Value<int>? id,
    Value<int>? journeyId,
    Value<WaypointKind>? kind,
    Value<DateTime>? createdAt,
    Value<double>? latitude,
    Value<double>? longitude,
    Value<double?>? accuracy,
    Value<double?>? altitude,
    Value<DateTime?>? fixTime,
    Value<String?>? name,
    Value<String?>? note,
  }) {
    return WaypointsCompanion(
      id: id ?? this.id,
      journeyId: journeyId ?? this.journeyId,
      kind: kind ?? this.kind,
      createdAt: createdAt ?? this.createdAt,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      altitude: altitude ?? this.altitude,
      fixTime: fixTime ?? this.fixTime,
      name: name ?? this.name,
      note: note ?? this.note,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (journeyId.present) {
      map['journey_id'] = Variable<int>(journeyId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        Waypoints.$converterkind.toSql(kind.value),
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(
        Waypoints.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (accuracy.present) {
      map['accuracy'] = Variable<double>(accuracy.value);
    }
    if (altitude.present) {
      map['altitude'] = Variable<double>(altitude.value);
    }
    if (fixTime.present) {
      map['fix_time'] = Variable<int>(
        Waypoints.$converterfixTimen.toSql(fixTime.value),
      );
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WaypointsCompanion(')
          ..write('id: $id, ')
          ..write('journeyId: $journeyId, ')
          ..write('kind: $kind, ')
          ..write('createdAt: $createdAt, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('accuracy: $accuracy, ')
          ..write('altitude: $altitude, ')
          ..write('fixTime: $fixTime, ')
          ..write('name: $name, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }
}

class Routes extends Table with TableInfo<Routes, RouteRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Routes(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _journeyIdMeta = const VerificationMeta(
    'journeyId',
  );
  late final GeneratedColumn<int> journeyId = GeneratedColumn<int>(
    'journey_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints:
        'NOT NULL PRIMARY KEY REFERENCES journeys(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _destinationMeta = const VerificationMeta(
    'destination',
  );
  late final GeneratedColumn<String> destination = GeneratedColumn<String>(
    'destination',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _destinationDetailMeta = const VerificationMeta(
    'destinationDetail',
  );
  late final GeneratedColumn<String> destinationDetail =
      GeneratedColumn<String>(
        'destination_detail',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        $customConstraints: '',
      );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  late final GeneratedColumnWithTypeConverter<RouteKind?, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        $customConstraints: '',
      ).withConverter<RouteKind?>(Routes.$converterkindn);
  static const VerificationMeta _providerMeta = const VerificationMeta(
    'provider',
  );
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
    'provider',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  late final GeneratedColumnWithTypeConverter<DateTime?, int> computedAt =
      GeneratedColumn<int>(
        'computed_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        $customConstraints: '',
      ).withConverter<DateTime?>(Routes.$convertercomputedAtn);
  static const VerificationMeta _metersMeta = const VerificationMeta('meters');
  late final GeneratedColumn<double> meters = GeneratedColumn<double>(
    'meters',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _secondsMeta = const VerificationMeta(
    'seconds',
  );
  late final GeneratedColumn<double> seconds = GeneratedColumn<double>(
    'seconds',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _geometryMeta = const VerificationMeta(
    'geometry',
  );
  late final GeneratedColumn<String> geometry = GeneratedColumn<String>(
    'geometry',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [
    journeyId,
    destination,
    destinationDetail,
    latitude,
    longitude,
    kind,
    provider,
    computedAt,
    meters,
    seconds,
    geometry,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'routes';
  @override
  VerificationContext validateIntegrity(
    Insertable<RouteRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('journey_id')) {
      context.handle(
        _journeyIdMeta,
        journeyId.isAcceptableOrUnknown(data['journey_id']!, _journeyIdMeta),
      );
    }
    if (data.containsKey('destination')) {
      context.handle(
        _destinationMeta,
        destination.isAcceptableOrUnknown(
          data['destination']!,
          _destinationMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_destinationMeta);
    }
    if (data.containsKey('destination_detail')) {
      context.handle(
        _destinationDetailMeta,
        destinationDetail.isAcceptableOrUnknown(
          data['destination_detail']!,
          _destinationDetailMeta,
        ),
      );
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('provider')) {
      context.handle(
        _providerMeta,
        provider.isAcceptableOrUnknown(data['provider']!, _providerMeta),
      );
    }
    if (data.containsKey('meters')) {
      context.handle(
        _metersMeta,
        meters.isAcceptableOrUnknown(data['meters']!, _metersMeta),
      );
    }
    if (data.containsKey('seconds')) {
      context.handle(
        _secondsMeta,
        seconds.isAcceptableOrUnknown(data['seconds']!, _secondsMeta),
      );
    }
    if (data.containsKey('geometry')) {
      context.handle(
        _geometryMeta,
        geometry.isAcceptableOrUnknown(data['geometry']!, _geometryMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {journeyId};
  @override
  RouteRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RouteRow(
      journeyId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}journey_id'],
      )!,
      destination: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}destination'],
      )!,
      destinationDetail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}destination_detail'],
      ),
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      )!,
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      )!,
      kind: Routes.$converterkindn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        ),
      ),
      provider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider'],
      ),
      computedAt: Routes.$convertercomputedAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}computed_at'],
        ),
      ),
      meters: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}meters'],
      ),
      seconds: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}seconds'],
      ),
      geometry: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}geometry'],
      ),
    );
  }

  @override
  Routes createAlias(String alias) {
    return Routes(attachedDatabase, alias);
  }

  static JsonTypeConverter2<RouteKind, String, String> $converterkind =
      const RouteKindByName();
  static JsonTypeConverter2<RouteKind?, String?, String?> $converterkindn =
      JsonTypeConverter2.asNullable($converterkind);
  static TypeConverter<DateTime, int> $convertercomputedAt = const UtcMillis();
  static TypeConverter<DateTime?, int?> $convertercomputedAtn =
      NullAwareTypeConverter.wrap($convertercomputedAt);
  @override
  bool get dontWriteConstraints => true;
}

class RouteRow extends DataClass implements Insertable<RouteRow> {
  final int journeyId;
  final String destination;
  final String? destinationDetail;
  final double latitude;
  final double longitude;

  /// Stored by name (see waypoints.kind).
  final RouteKind? kind;
  final String? provider;
  final DateTime? computedAt;
  final double? meters;
  final double? seconds;

  /// The line, as a polyline with six decimals.
  final String? geometry;
  const RouteRow({
    required this.journeyId,
    required this.destination,
    this.destinationDetail,
    required this.latitude,
    required this.longitude,
    this.kind,
    this.provider,
    this.computedAt,
    this.meters,
    this.seconds,
    this.geometry,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['journey_id'] = Variable<int>(journeyId);
    map['destination'] = Variable<String>(destination);
    if (!nullToAbsent || destinationDetail != null) {
      map['destination_detail'] = Variable<String>(destinationDetail);
    }
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    if (!nullToAbsent || kind != null) {
      map['kind'] = Variable<String>(Routes.$converterkindn.toSql(kind));
    }
    if (!nullToAbsent || provider != null) {
      map['provider'] = Variable<String>(provider);
    }
    if (!nullToAbsent || computedAt != null) {
      map['computed_at'] = Variable<int>(
        Routes.$convertercomputedAtn.toSql(computedAt),
      );
    }
    if (!nullToAbsent || meters != null) {
      map['meters'] = Variable<double>(meters);
    }
    if (!nullToAbsent || seconds != null) {
      map['seconds'] = Variable<double>(seconds);
    }
    if (!nullToAbsent || geometry != null) {
      map['geometry'] = Variable<String>(geometry);
    }
    return map;
  }

  RoutesCompanion toCompanion(bool nullToAbsent) {
    return RoutesCompanion(
      journeyId: Value(journeyId),
      destination: Value(destination),
      destinationDetail: destinationDetail == null && nullToAbsent
          ? const Value.absent()
          : Value(destinationDetail),
      latitude: Value(latitude),
      longitude: Value(longitude),
      kind: kind == null && nullToAbsent ? const Value.absent() : Value(kind),
      provider: provider == null && nullToAbsent
          ? const Value.absent()
          : Value(provider),
      computedAt: computedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(computedAt),
      meters: meters == null && nullToAbsent
          ? const Value.absent()
          : Value(meters),
      seconds: seconds == null && nullToAbsent
          ? const Value.absent()
          : Value(seconds),
      geometry: geometry == null && nullToAbsent
          ? const Value.absent()
          : Value(geometry),
    );
  }

  factory RouteRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RouteRow(
      journeyId: serializer.fromJson<int>(json['journey_id']),
      destination: serializer.fromJson<String>(json['destination']),
      destinationDetail: serializer.fromJson<String?>(
        json['destination_detail'],
      ),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      kind: Routes.$converterkindn.fromJson(
        serializer.fromJson<String?>(json['kind']),
      ),
      provider: serializer.fromJson<String?>(json['provider']),
      computedAt: serializer.fromJson<DateTime?>(json['computed_at']),
      meters: serializer.fromJson<double?>(json['meters']),
      seconds: serializer.fromJson<double?>(json['seconds']),
      geometry: serializer.fromJson<String?>(json['geometry']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'journey_id': serializer.toJson<int>(journeyId),
      'destination': serializer.toJson<String>(destination),
      'destination_detail': serializer.toJson<String?>(destinationDetail),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'kind': serializer.toJson<String?>(Routes.$converterkindn.toJson(kind)),
      'provider': serializer.toJson<String?>(provider),
      'computed_at': serializer.toJson<DateTime?>(computedAt),
      'meters': serializer.toJson<double?>(meters),
      'seconds': serializer.toJson<double?>(seconds),
      'geometry': serializer.toJson<String?>(geometry),
    };
  }

  RouteRow copyWith({
    int? journeyId,
    String? destination,
    Value<String?> destinationDetail = const Value.absent(),
    double? latitude,
    double? longitude,
    Value<RouteKind?> kind = const Value.absent(),
    Value<String?> provider = const Value.absent(),
    Value<DateTime?> computedAt = const Value.absent(),
    Value<double?> meters = const Value.absent(),
    Value<double?> seconds = const Value.absent(),
    Value<String?> geometry = const Value.absent(),
  }) => RouteRow(
    journeyId: journeyId ?? this.journeyId,
    destination: destination ?? this.destination,
    destinationDetail: destinationDetail.present
        ? destinationDetail.value
        : this.destinationDetail,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    kind: kind.present ? kind.value : this.kind,
    provider: provider.present ? provider.value : this.provider,
    computedAt: computedAt.present ? computedAt.value : this.computedAt,
    meters: meters.present ? meters.value : this.meters,
    seconds: seconds.present ? seconds.value : this.seconds,
    geometry: geometry.present ? geometry.value : this.geometry,
  );
  RouteRow copyWithCompanion(RoutesCompanion data) {
    return RouteRow(
      journeyId: data.journeyId.present ? data.journeyId.value : this.journeyId,
      destination: data.destination.present
          ? data.destination.value
          : this.destination,
      destinationDetail: data.destinationDetail.present
          ? data.destinationDetail.value
          : this.destinationDetail,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      kind: data.kind.present ? data.kind.value : this.kind,
      provider: data.provider.present ? data.provider.value : this.provider,
      computedAt: data.computedAt.present
          ? data.computedAt.value
          : this.computedAt,
      meters: data.meters.present ? data.meters.value : this.meters,
      seconds: data.seconds.present ? data.seconds.value : this.seconds,
      geometry: data.geometry.present ? data.geometry.value : this.geometry,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RouteRow(')
          ..write('journeyId: $journeyId, ')
          ..write('destination: $destination, ')
          ..write('destinationDetail: $destinationDetail, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('kind: $kind, ')
          ..write('provider: $provider, ')
          ..write('computedAt: $computedAt, ')
          ..write('meters: $meters, ')
          ..write('seconds: $seconds, ')
          ..write('geometry: $geometry')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    journeyId,
    destination,
    destinationDetail,
    latitude,
    longitude,
    kind,
    provider,
    computedAt,
    meters,
    seconds,
    geometry,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RouteRow &&
          other.journeyId == this.journeyId &&
          other.destination == this.destination &&
          other.destinationDetail == this.destinationDetail &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.kind == this.kind &&
          other.provider == this.provider &&
          other.computedAt == this.computedAt &&
          other.meters == this.meters &&
          other.seconds == this.seconds &&
          other.geometry == this.geometry);
}

class RoutesCompanion extends UpdateCompanion<RouteRow> {
  final Value<int> journeyId;
  final Value<String> destination;
  final Value<String?> destinationDetail;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<RouteKind?> kind;
  final Value<String?> provider;
  final Value<DateTime?> computedAt;
  final Value<double?> meters;
  final Value<double?> seconds;
  final Value<String?> geometry;
  const RoutesCompanion({
    this.journeyId = const Value.absent(),
    this.destination = const Value.absent(),
    this.destinationDetail = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.kind = const Value.absent(),
    this.provider = const Value.absent(),
    this.computedAt = const Value.absent(),
    this.meters = const Value.absent(),
    this.seconds = const Value.absent(),
    this.geometry = const Value.absent(),
  });
  RoutesCompanion.insert({
    this.journeyId = const Value.absent(),
    required String destination,
    this.destinationDetail = const Value.absent(),
    required double latitude,
    required double longitude,
    this.kind = const Value.absent(),
    this.provider = const Value.absent(),
    this.computedAt = const Value.absent(),
    this.meters = const Value.absent(),
    this.seconds = const Value.absent(),
    this.geometry = const Value.absent(),
  }) : destination = Value(destination),
       latitude = Value(latitude),
       longitude = Value(longitude);
  static Insertable<RouteRow> custom({
    Expression<int>? journeyId,
    Expression<String>? destination,
    Expression<String>? destinationDetail,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<String>? kind,
    Expression<String>? provider,
    Expression<int>? computedAt,
    Expression<double>? meters,
    Expression<double>? seconds,
    Expression<String>? geometry,
  }) {
    return RawValuesInsertable({
      if (journeyId != null) 'journey_id': journeyId,
      if (destination != null) 'destination': destination,
      if (destinationDetail != null) 'destination_detail': destinationDetail,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (kind != null) 'kind': kind,
      if (provider != null) 'provider': provider,
      if (computedAt != null) 'computed_at': computedAt,
      if (meters != null) 'meters': meters,
      if (seconds != null) 'seconds': seconds,
      if (geometry != null) 'geometry': geometry,
    });
  }

  RoutesCompanion copyWith({
    Value<int>? journeyId,
    Value<String>? destination,
    Value<String?>? destinationDetail,
    Value<double>? latitude,
    Value<double>? longitude,
    Value<RouteKind?>? kind,
    Value<String?>? provider,
    Value<DateTime?>? computedAt,
    Value<double?>? meters,
    Value<double?>? seconds,
    Value<String?>? geometry,
  }) {
    return RoutesCompanion(
      journeyId: journeyId ?? this.journeyId,
      destination: destination ?? this.destination,
      destinationDetail: destinationDetail ?? this.destinationDetail,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      kind: kind ?? this.kind,
      provider: provider ?? this.provider,
      computedAt: computedAt ?? this.computedAt,
      meters: meters ?? this.meters,
      seconds: seconds ?? this.seconds,
      geometry: geometry ?? this.geometry,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (journeyId.present) {
      map['journey_id'] = Variable<int>(journeyId.value);
    }
    if (destination.present) {
      map['destination'] = Variable<String>(destination.value);
    }
    if (destinationDetail.present) {
      map['destination_detail'] = Variable<String>(destinationDetail.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(Routes.$converterkindn.toSql(kind.value));
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (computedAt.present) {
      map['computed_at'] = Variable<int>(
        Routes.$convertercomputedAtn.toSql(computedAt.value),
      );
    }
    if (meters.present) {
      map['meters'] = Variable<double>(meters.value);
    }
    if (seconds.present) {
      map['seconds'] = Variable<double>(seconds.value);
    }
    if (geometry.present) {
      map['geometry'] = Variable<String>(geometry.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RoutesCompanion(')
          ..write('journeyId: $journeyId, ')
          ..write('destination: $destination, ')
          ..write('destinationDetail: $destinationDetail, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('kind: $kind, ')
          ..write('provider: $provider, ')
          ..write('computedAt: $computedAt, ')
          ..write('meters: $meters, ')
          ..write('seconds: $seconds, ')
          ..write('geometry: $geometry')
          ..write(')'))
        .toString();
  }
}

class RecentPlaces extends Table with TableInfo<RecentPlaces, RecentPlaceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  RecentPlaces(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _detailMeta = const VerificationMeta('detail');
  late final GeneratedColumn<String> detail = GeneratedColumn<String>(
    'detail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  late final GeneratedColumnWithTypeConverter<DateTime, int> usedAt =
      GeneratedColumn<int>(
        'used_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
        $customConstraints: 'NOT NULL',
      ).withConverter<DateTime>(RecentPlaces.$converterusedAt);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    detail,
    latitude,
    longitude,
    usedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recent_places';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecentPlaceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('detail')) {
      context.handle(
        _detailMeta,
        detail.isAcceptableOrUnknown(data['detail']!, _detailMeta),
      );
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RecentPlaceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecentPlaceRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      detail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}detail'],
      ),
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      )!,
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      )!,
      usedAt: RecentPlaces.$converterusedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}used_at'],
        )!,
      ),
    );
  }

  @override
  RecentPlaces createAlias(String alias) {
    return RecentPlaces(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterusedAt = const UtcMillis();
  @override
  bool get dontWriteConstraints => true;
}

class RecentPlaceRow extends DataClass implements Insertable<RecentPlaceRow> {
  final int id;
  final String name;
  final String? detail;
  final double latitude;
  final double longitude;
  final DateTime usedAt;
  const RecentPlaceRow({
    required this.id,
    required this.name,
    this.detail,
    required this.latitude,
    required this.longitude,
    required this.usedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || detail != null) {
      map['detail'] = Variable<String>(detail);
    }
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    {
      map['used_at'] = Variable<int>(
        RecentPlaces.$converterusedAt.toSql(usedAt),
      );
    }
    return map;
  }

  RecentPlacesCompanion toCompanion(bool nullToAbsent) {
    return RecentPlacesCompanion(
      id: Value(id),
      name: Value(name),
      detail: detail == null && nullToAbsent
          ? const Value.absent()
          : Value(detail),
      latitude: Value(latitude),
      longitude: Value(longitude),
      usedAt: Value(usedAt),
    );
  }

  factory RecentPlaceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecentPlaceRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      detail: serializer.fromJson<String?>(json['detail']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      usedAt: serializer.fromJson<DateTime>(json['used_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'detail': serializer.toJson<String?>(detail),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'used_at': serializer.toJson<DateTime>(usedAt),
    };
  }

  RecentPlaceRow copyWith({
    int? id,
    String? name,
    Value<String?> detail = const Value.absent(),
    double? latitude,
    double? longitude,
    DateTime? usedAt,
  }) => RecentPlaceRow(
    id: id ?? this.id,
    name: name ?? this.name,
    detail: detail.present ? detail.value : this.detail,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    usedAt: usedAt ?? this.usedAt,
  );
  RecentPlaceRow copyWithCompanion(RecentPlacesCompanion data) {
    return RecentPlaceRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      detail: data.detail.present ? data.detail.value : this.detail,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      usedAt: data.usedAt.present ? data.usedAt.value : this.usedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecentPlaceRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('detail: $detail, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('usedAt: $usedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, detail, latitude, longitude, usedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecentPlaceRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.detail == this.detail &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.usedAt == this.usedAt);
}

class RecentPlacesCompanion extends UpdateCompanion<RecentPlaceRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> detail;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<DateTime> usedAt;
  const RecentPlacesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.detail = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.usedAt = const Value.absent(),
  });
  RecentPlacesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.detail = const Value.absent(),
    required double latitude,
    required double longitude,
    required DateTime usedAt,
  }) : name = Value(name),
       latitude = Value(latitude),
       longitude = Value(longitude),
       usedAt = Value(usedAt);
  static Insertable<RecentPlaceRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? detail,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<int>? usedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (detail != null) 'detail': detail,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (usedAt != null) 'used_at': usedAt,
    });
  }

  RecentPlacesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? detail,
    Value<double>? latitude,
    Value<double>? longitude,
    Value<DateTime>? usedAt,
  }) {
    return RecentPlacesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      detail: detail ?? this.detail,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      usedAt: usedAt ?? this.usedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (detail.present) {
      map['detail'] = Variable<String>(detail.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (usedAt.present) {
      map['used_at'] = Variable<int>(
        RecentPlaces.$converterusedAt.toSql(usedAt.value),
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecentPlacesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('detail: $detail, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('usedAt: $usedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$JourneyStore extends GeneratedDatabase {
  _$JourneyStore(QueryExecutor e) : super(e);
  late final Journeys journeys = Journeys(this);
  late final Index oneActiveJourney = Index(
    'one_active_journey',
    'CREATE UNIQUE INDEX IF NOT EXISTS one_active_journey ON journeys (status IN (\'recording\', \'paused\')) WHERE status IN (\'recording\', \'paused\')',
  );
  late final Segments segments = Segments(this);
  late final TrackPoints trackPoints = TrackPoints(this);
  late final Waypoints waypoints = Waypoints(this);
  late final Index waypointsByJourney = Index(
    'waypoints_by_journey',
    'CREATE INDEX IF NOT EXISTS waypoints_by_journey ON waypoints (journey_id)',
  );
  late final Routes routes = Routes(this);
  late final RecentPlaces recentPlaces = RecentPlaces(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    journeys,
    oneActiveJourney,
    segments,
    trackPoints,
    waypoints,
    waypointsByJourney,
    routes,
    recentPlaces,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'journeys',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('segments', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'journeys',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('track_points', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'journeys',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('waypoints', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'journeys',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('routes', kind: UpdateKind.delete)],
    ),
  ]);
}
