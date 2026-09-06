// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $OrdersTable extends Orders with TableInfo<$OrdersTable, OrderRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OrdersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _tableNumberMeta =
      const VerificationMeta('tableNumber');
  @override
  late final GeneratedColumn<int> tableNumber = GeneratedColumn<int>(
      'table_number', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
      'state', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant<String>('aperto'));
  static const VerificationMeta _stateRevisionCounterMeta =
      const VerificationMeta('stateRevisionCounter');
  @override
  late final GeneratedColumn<int> stateRevisionCounter = GeneratedColumn<int>(
      'state_revision_counter', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant<int>(0));
  static const VerificationMeta _stateRevisionDeviceMeta =
      const VerificationMeta('stateRevisionDevice');
  @override
  late final GeneratedColumn<String> stateRevisionDevice =
      GeneratedColumn<String>('state_revision_device', aliasedName, false,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          defaultValue: const Constant<String>(''));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        tableNumber,
        createdAt,
        status,
        state,
        stateRevisionCounter,
        stateRevisionDevice
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'orders';
  @override
  VerificationContext validateIntegrity(Insertable<OrderRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('table_number')) {
      context.handle(
          _tableNumberMeta,
          tableNumber.isAcceptableOrUnknown(
              data['table_number']!, _tableNumberMeta));
    } else if (isInserting) {
      context.missing(_tableNumberMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
          _stateMeta, state.isAcceptableOrUnknown(data['state']!, _stateMeta));
    }
    if (data.containsKey('state_revision_counter')) {
      context.handle(
          _stateRevisionCounterMeta,
          stateRevisionCounter.isAcceptableOrUnknown(
              data['state_revision_counter']!, _stateRevisionCounterMeta));
    }
    if (data.containsKey('state_revision_device')) {
      context.handle(
          _stateRevisionDeviceMeta,
          stateRevisionDevice.isAcceptableOrUnknown(
              data['state_revision_device']!, _stateRevisionDeviceMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OrderRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OrderRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      tableNumber: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}table_number'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      state: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}state'])!,
      stateRevisionCounter: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}state_revision_counter'])!,
      stateRevisionDevice: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}state_revision_device'])!,
    );
  }

  @override
  $OrdersTable createAlias(String alias) {
    return $OrdersTable(attachedDatabase, alias);
  }
}

class OrderRow extends DataClass implements Insertable<OrderRow> {
  final String id;
  final int tableNumber;

  /// Istante di creazione in **microsecondi** dall'epoca.
  ///
  /// `DateTime` in Dart ha precisione al microsecondo. Salvare secondi — il
  /// formato storico di Drift — o millisecondi troncherebbe, e uno store che
  /// tronca non supera la stessa suite di uno che non tronca. Il fuso non
  /// viene conservato: si legge sempre come ora locale.
  final int createdAt;

  /// Stato di sincronizzazione, locale a questo dispositivo.
  final String status;

  /// Stato del tavolo, condiviso fra i dispositivi.
  final String state;

  /// Revisione dell'ultimo cambio di stato, in due colonne piatte.
  ///
  /// Un valore composto scritto in una colonna sola — `"7@tablet-a"` — sarebbe
  /// più compatto e impossibile da ordinare in SQL. Separate si possono
  /// confrontare e indicizzare.
  final int stateRevisionCounter;
  final String stateRevisionDevice;
  const OrderRow(
      {required this.id,
      required this.tableNumber,
      required this.createdAt,
      required this.status,
      required this.state,
      required this.stateRevisionCounter,
      required this.stateRevisionDevice});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['table_number'] = Variable<int>(tableNumber);
    map['created_at'] = Variable<int>(createdAt);
    map['status'] = Variable<String>(status);
    map['state'] = Variable<String>(state);
    map['state_revision_counter'] = Variable<int>(stateRevisionCounter);
    map['state_revision_device'] = Variable<String>(stateRevisionDevice);
    return map;
  }

  OrdersCompanion toCompanion(bool nullToAbsent) {
    return OrdersCompanion(
      id: Value(id),
      tableNumber: Value(tableNumber),
      createdAt: Value(createdAt),
      status: Value(status),
      state: Value(state),
      stateRevisionCounter: Value(stateRevisionCounter),
      stateRevisionDevice: Value(stateRevisionDevice),
    );
  }

  factory OrderRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OrderRow(
      id: serializer.fromJson<String>(json['id']),
      tableNumber: serializer.fromJson<int>(json['tableNumber']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      status: serializer.fromJson<String>(json['status']),
      state: serializer.fromJson<String>(json['state']),
      stateRevisionCounter:
          serializer.fromJson<int>(json['stateRevisionCounter']),
      stateRevisionDevice:
          serializer.fromJson<String>(json['stateRevisionDevice']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'tableNumber': serializer.toJson<int>(tableNumber),
      'createdAt': serializer.toJson<int>(createdAt),
      'status': serializer.toJson<String>(status),
      'state': serializer.toJson<String>(state),
      'stateRevisionCounter': serializer.toJson<int>(stateRevisionCounter),
      'stateRevisionDevice': serializer.toJson<String>(stateRevisionDevice),
    };
  }

  OrderRow copyWith(
          {String? id,
          int? tableNumber,
          int? createdAt,
          String? status,
          String? state,
          int? stateRevisionCounter,
          String? stateRevisionDevice}) =>
      OrderRow(
        id: id ?? this.id,
        tableNumber: tableNumber ?? this.tableNumber,
        createdAt: createdAt ?? this.createdAt,
        status: status ?? this.status,
        state: state ?? this.state,
        stateRevisionCounter: stateRevisionCounter ?? this.stateRevisionCounter,
        stateRevisionDevice: stateRevisionDevice ?? this.stateRevisionDevice,
      );
  OrderRow copyWithCompanion(OrdersCompanion data) {
    return OrderRow(
      id: data.id.present ? data.id.value : this.id,
      tableNumber:
          data.tableNumber.present ? data.tableNumber.value : this.tableNumber,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      status: data.status.present ? data.status.value : this.status,
      state: data.state.present ? data.state.value : this.state,
      stateRevisionCounter: data.stateRevisionCounter.present
          ? data.stateRevisionCounter.value
          : this.stateRevisionCounter,
      stateRevisionDevice: data.stateRevisionDevice.present
          ? data.stateRevisionDevice.value
          : this.stateRevisionDevice,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OrderRow(')
          ..write('id: $id, ')
          ..write('tableNumber: $tableNumber, ')
          ..write('createdAt: $createdAt, ')
          ..write('status: $status, ')
          ..write('state: $state, ')
          ..write('stateRevisionCounter: $stateRevisionCounter, ')
          ..write('stateRevisionDevice: $stateRevisionDevice')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, tableNumber, createdAt, status, state,
      stateRevisionCounter, stateRevisionDevice);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OrderRow &&
          other.id == this.id &&
          other.tableNumber == this.tableNumber &&
          other.createdAt == this.createdAt &&
          other.status == this.status &&
          other.state == this.state &&
          other.stateRevisionCounter == this.stateRevisionCounter &&
          other.stateRevisionDevice == this.stateRevisionDevice);
}

class OrdersCompanion extends UpdateCompanion<OrderRow> {
  final Value<String> id;
  final Value<int> tableNumber;
  final Value<int> createdAt;
  final Value<String> status;
  final Value<String> state;
  final Value<int> stateRevisionCounter;
  final Value<String> stateRevisionDevice;
  final Value<int> rowid;
  const OrdersCompanion({
    this.id = const Value.absent(),
    this.tableNumber = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.status = const Value.absent(),
    this.state = const Value.absent(),
    this.stateRevisionCounter = const Value.absent(),
    this.stateRevisionDevice = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OrdersCompanion.insert({
    required String id,
    required int tableNumber,
    required int createdAt,
    required String status,
    this.state = const Value.absent(),
    this.stateRevisionCounter = const Value.absent(),
    this.stateRevisionDevice = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        tableNumber = Value(tableNumber),
        createdAt = Value(createdAt),
        status = Value(status);
  static Insertable<OrderRow> custom({
    Expression<String>? id,
    Expression<int>? tableNumber,
    Expression<int>? createdAt,
    Expression<String>? status,
    Expression<String>? state,
    Expression<int>? stateRevisionCounter,
    Expression<String>? stateRevisionDevice,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (tableNumber != null) 'table_number': tableNumber,
      if (createdAt != null) 'created_at': createdAt,
      if (status != null) 'status': status,
      if (state != null) 'state': state,
      if (stateRevisionCounter != null)
        'state_revision_counter': stateRevisionCounter,
      if (stateRevisionDevice != null)
        'state_revision_device': stateRevisionDevice,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OrdersCompanion copyWith(
      {Value<String>? id,
      Value<int>? tableNumber,
      Value<int>? createdAt,
      Value<String>? status,
      Value<String>? state,
      Value<int>? stateRevisionCounter,
      Value<String>? stateRevisionDevice,
      Value<int>? rowid}) {
    return OrdersCompanion(
      id: id ?? this.id,
      tableNumber: tableNumber ?? this.tableNumber,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      state: state ?? this.state,
      stateRevisionCounter: stateRevisionCounter ?? this.stateRevisionCounter,
      stateRevisionDevice: stateRevisionDevice ?? this.stateRevisionDevice,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (tableNumber.present) {
      map['table_number'] = Variable<int>(tableNumber.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (stateRevisionCounter.present) {
      map['state_revision_counter'] = Variable<int>(stateRevisionCounter.value);
    }
    if (stateRevisionDevice.present) {
      map['state_revision_device'] =
          Variable<String>(stateRevisionDevice.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OrdersCompanion(')
          ..write('id: $id, ')
          ..write('tableNumber: $tableNumber, ')
          ..write('createdAt: $createdAt, ')
          ..write('status: $status, ')
          ..write('state: $state, ')
          ..write('stateRevisionCounter: $stateRevisionCounter, ')
          ..write('stateRevisionDevice: $stateRevisionDevice, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OrderLinesTable extends OrderLines
    with TableInfo<$OrderLinesTable, OrderLineRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OrderLinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _orderIdMeta =
      const VerificationMeta('orderId');
  @override
  late final GeneratedColumn<String> orderId = GeneratedColumn<String>(
      'order_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES orders (id) ON DELETE CASCADE'));
  static const VerificationMeta _positionMeta =
      const VerificationMeta('position');
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
      'position', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _lineIdMeta = const VerificationMeta('lineId');
  @override
  late final GeneratedColumn<String> lineId = GeneratedColumn<String>(
      'line_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant<String>(''));
  static const VerificationMeta _addedAtCounterMeta =
      const VerificationMeta('addedAtCounter');
  @override
  late final GeneratedColumn<int> addedAtCounter = GeneratedColumn<int>(
      'added_at_counter', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant<int>(0));
  static const VerificationMeta _addedAtDeviceMeta =
      const VerificationMeta('addedAtDevice');
  @override
  late final GeneratedColumn<String> addedAtDevice = GeneratedColumn<String>(
      'added_at_device', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant<String>(''));
  static const VerificationMeta _productIdMeta =
      const VerificationMeta('productId');
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
      'product_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _quantityMeta =
      const VerificationMeta('quantity');
  @override
  late final GeneratedColumn<int> quantity = GeneratedColumn<int>(
      'quantity', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _unitPriceCentsMeta =
      const VerificationMeta('unitPriceCents');
  @override
  late final GeneratedColumn<int> unitPriceCents = GeneratedColumn<int>(
      'unit_price_cents', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        orderId,
        position,
        lineId,
        addedAtCounter,
        addedAtDevice,
        productId,
        description,
        quantity,
        unitPriceCents
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'order_lines';
  @override
  VerificationContext validateIntegrity(Insertable<OrderLineRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('order_id')) {
      context.handle(_orderIdMeta,
          orderId.isAcceptableOrUnknown(data['order_id']!, _orderIdMeta));
    } else if (isInserting) {
      context.missing(_orderIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(_positionMeta,
          position.isAcceptableOrUnknown(data['position']!, _positionMeta));
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('line_id')) {
      context.handle(_lineIdMeta,
          lineId.isAcceptableOrUnknown(data['line_id']!, _lineIdMeta));
    }
    if (data.containsKey('added_at_counter')) {
      context.handle(
          _addedAtCounterMeta,
          addedAtCounter.isAcceptableOrUnknown(
              data['added_at_counter']!, _addedAtCounterMeta));
    }
    if (data.containsKey('added_at_device')) {
      context.handle(
          _addedAtDeviceMeta,
          addedAtDevice.isAcceptableOrUnknown(
              data['added_at_device']!, _addedAtDeviceMeta));
    }
    if (data.containsKey('product_id')) {
      context.handle(_productIdMeta,
          productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta));
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('quantity')) {
      context.handle(_quantityMeta,
          quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta));
    } else if (isInserting) {
      context.missing(_quantityMeta);
    }
    if (data.containsKey('unit_price_cents')) {
      context.handle(
          _unitPriceCentsMeta,
          unitPriceCents.isAcceptableOrUnknown(
              data['unit_price_cents']!, _unitPriceCentsMeta));
    } else if (isInserting) {
      context.missing(_unitPriceCentsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {orderId, position};
  @override
  OrderLineRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OrderLineRow(
      orderId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}order_id'])!,
      position: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}position'])!,
      lineId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}line_id'])!,
      addedAtCounter: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}added_at_counter'])!,
      addedAtDevice: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}added_at_device'])!,
      productId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_id'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description'])!,
      quantity: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}quantity'])!,
      unitPriceCents: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}unit_price_cents'])!,
    );
  }

  @override
  $OrderLinesTable createAlias(String alias) {
    return $OrderLinesTable(attachedDatabase, alias);
  }
}

class OrderLineRow extends DataClass implements Insertable<OrderLineRow> {
  final String orderId;

  /// Posizione della riga dentro l'ordine.
  ///
  /// `Order.lines` è una lista *ordinata*, le righe di una tabella SQL non
  /// hanno ordine. Senza questa colonna l'ordine delle righe dipenderebbe da
  /// come il motore decide di restituirle.
  final int position;

  /// Identificativo della riga, stabile fra i dispositivi.
  ///
  /// Non è la chiave primaria e non lo diventa: la posizione dipende
  /// dall'ordine locale e cambia a ogni fusione, l'id no. Serve all'unione
  /// append-only, che senza di esso duplicherebbe la stessa riga a ogni
  /// sincronizzazione.
  final String lineId;

  /// Revisione a cui la riga è stata aggiunta.
  final int addedAtCounter;
  final String addedAtDevice;
  final String productId;
  final String description;
  final int quantity;
  final int unitPriceCents;
  const OrderLineRow(
      {required this.orderId,
      required this.position,
      required this.lineId,
      required this.addedAtCounter,
      required this.addedAtDevice,
      required this.productId,
      required this.description,
      required this.quantity,
      required this.unitPriceCents});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['order_id'] = Variable<String>(orderId);
    map['position'] = Variable<int>(position);
    map['line_id'] = Variable<String>(lineId);
    map['added_at_counter'] = Variable<int>(addedAtCounter);
    map['added_at_device'] = Variable<String>(addedAtDevice);
    map['product_id'] = Variable<String>(productId);
    map['description'] = Variable<String>(description);
    map['quantity'] = Variable<int>(quantity);
    map['unit_price_cents'] = Variable<int>(unitPriceCents);
    return map;
  }

  OrderLinesCompanion toCompanion(bool nullToAbsent) {
    return OrderLinesCompanion(
      orderId: Value(orderId),
      position: Value(position),
      lineId: Value(lineId),
      addedAtCounter: Value(addedAtCounter),
      addedAtDevice: Value(addedAtDevice),
      productId: Value(productId),
      description: Value(description),
      quantity: Value(quantity),
      unitPriceCents: Value(unitPriceCents),
    );
  }

  factory OrderLineRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OrderLineRow(
      orderId: serializer.fromJson<String>(json['orderId']),
      position: serializer.fromJson<int>(json['position']),
      lineId: serializer.fromJson<String>(json['lineId']),
      addedAtCounter: serializer.fromJson<int>(json['addedAtCounter']),
      addedAtDevice: serializer.fromJson<String>(json['addedAtDevice']),
      productId: serializer.fromJson<String>(json['productId']),
      description: serializer.fromJson<String>(json['description']),
      quantity: serializer.fromJson<int>(json['quantity']),
      unitPriceCents: serializer.fromJson<int>(json['unitPriceCents']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'orderId': serializer.toJson<String>(orderId),
      'position': serializer.toJson<int>(position),
      'lineId': serializer.toJson<String>(lineId),
      'addedAtCounter': serializer.toJson<int>(addedAtCounter),
      'addedAtDevice': serializer.toJson<String>(addedAtDevice),
      'productId': serializer.toJson<String>(productId),
      'description': serializer.toJson<String>(description),
      'quantity': serializer.toJson<int>(quantity),
      'unitPriceCents': serializer.toJson<int>(unitPriceCents),
    };
  }

  OrderLineRow copyWith(
          {String? orderId,
          int? position,
          String? lineId,
          int? addedAtCounter,
          String? addedAtDevice,
          String? productId,
          String? description,
          int? quantity,
          int? unitPriceCents}) =>
      OrderLineRow(
        orderId: orderId ?? this.orderId,
        position: position ?? this.position,
        lineId: lineId ?? this.lineId,
        addedAtCounter: addedAtCounter ?? this.addedAtCounter,
        addedAtDevice: addedAtDevice ?? this.addedAtDevice,
        productId: productId ?? this.productId,
        description: description ?? this.description,
        quantity: quantity ?? this.quantity,
        unitPriceCents: unitPriceCents ?? this.unitPriceCents,
      );
  OrderLineRow copyWithCompanion(OrderLinesCompanion data) {
    return OrderLineRow(
      orderId: data.orderId.present ? data.orderId.value : this.orderId,
      position: data.position.present ? data.position.value : this.position,
      lineId: data.lineId.present ? data.lineId.value : this.lineId,
      addedAtCounter: data.addedAtCounter.present
          ? data.addedAtCounter.value
          : this.addedAtCounter,
      addedAtDevice: data.addedAtDevice.present
          ? data.addedAtDevice.value
          : this.addedAtDevice,
      productId: data.productId.present ? data.productId.value : this.productId,
      description:
          data.description.present ? data.description.value : this.description,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      unitPriceCents: data.unitPriceCents.present
          ? data.unitPriceCents.value
          : this.unitPriceCents,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OrderLineRow(')
          ..write('orderId: $orderId, ')
          ..write('position: $position, ')
          ..write('lineId: $lineId, ')
          ..write('addedAtCounter: $addedAtCounter, ')
          ..write('addedAtDevice: $addedAtDevice, ')
          ..write('productId: $productId, ')
          ..write('description: $description, ')
          ..write('quantity: $quantity, ')
          ..write('unitPriceCents: $unitPriceCents')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(orderId, position, lineId, addedAtCounter,
      addedAtDevice, productId, description, quantity, unitPriceCents);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OrderLineRow &&
          other.orderId == this.orderId &&
          other.position == this.position &&
          other.lineId == this.lineId &&
          other.addedAtCounter == this.addedAtCounter &&
          other.addedAtDevice == this.addedAtDevice &&
          other.productId == this.productId &&
          other.description == this.description &&
          other.quantity == this.quantity &&
          other.unitPriceCents == this.unitPriceCents);
}

class OrderLinesCompanion extends UpdateCompanion<OrderLineRow> {
  final Value<String> orderId;
  final Value<int> position;
  final Value<String> lineId;
  final Value<int> addedAtCounter;
  final Value<String> addedAtDevice;
  final Value<String> productId;
  final Value<String> description;
  final Value<int> quantity;
  final Value<int> unitPriceCents;
  final Value<int> rowid;
  const OrderLinesCompanion({
    this.orderId = const Value.absent(),
    this.position = const Value.absent(),
    this.lineId = const Value.absent(),
    this.addedAtCounter = const Value.absent(),
    this.addedAtDevice = const Value.absent(),
    this.productId = const Value.absent(),
    this.description = const Value.absent(),
    this.quantity = const Value.absent(),
    this.unitPriceCents = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OrderLinesCompanion.insert({
    required String orderId,
    required int position,
    this.lineId = const Value.absent(),
    this.addedAtCounter = const Value.absent(),
    this.addedAtDevice = const Value.absent(),
    required String productId,
    required String description,
    required int quantity,
    required int unitPriceCents,
    this.rowid = const Value.absent(),
  })  : orderId = Value(orderId),
        position = Value(position),
        productId = Value(productId),
        description = Value(description),
        quantity = Value(quantity),
        unitPriceCents = Value(unitPriceCents);
  static Insertable<OrderLineRow> custom({
    Expression<String>? orderId,
    Expression<int>? position,
    Expression<String>? lineId,
    Expression<int>? addedAtCounter,
    Expression<String>? addedAtDevice,
    Expression<String>? productId,
    Expression<String>? description,
    Expression<int>? quantity,
    Expression<int>? unitPriceCents,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (orderId != null) 'order_id': orderId,
      if (position != null) 'position': position,
      if (lineId != null) 'line_id': lineId,
      if (addedAtCounter != null) 'added_at_counter': addedAtCounter,
      if (addedAtDevice != null) 'added_at_device': addedAtDevice,
      if (productId != null) 'product_id': productId,
      if (description != null) 'description': description,
      if (quantity != null) 'quantity': quantity,
      if (unitPriceCents != null) 'unit_price_cents': unitPriceCents,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OrderLinesCompanion copyWith(
      {Value<String>? orderId,
      Value<int>? position,
      Value<String>? lineId,
      Value<int>? addedAtCounter,
      Value<String>? addedAtDevice,
      Value<String>? productId,
      Value<String>? description,
      Value<int>? quantity,
      Value<int>? unitPriceCents,
      Value<int>? rowid}) {
    return OrderLinesCompanion(
      orderId: orderId ?? this.orderId,
      position: position ?? this.position,
      lineId: lineId ?? this.lineId,
      addedAtCounter: addedAtCounter ?? this.addedAtCounter,
      addedAtDevice: addedAtDevice ?? this.addedAtDevice,
      productId: productId ?? this.productId,
      description: description ?? this.description,
      quantity: quantity ?? this.quantity,
      unitPriceCents: unitPriceCents ?? this.unitPriceCents,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (orderId.present) {
      map['order_id'] = Variable<String>(orderId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (lineId.present) {
      map['line_id'] = Variable<String>(lineId.value);
    }
    if (addedAtCounter.present) {
      map['added_at_counter'] = Variable<int>(addedAtCounter.value);
    }
    if (addedAtDevice.present) {
      map['added_at_device'] = Variable<String>(addedAtDevice.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<int>(quantity.value);
    }
    if (unitPriceCents.present) {
      map['unit_price_cents'] = Variable<int>(unitPriceCents.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OrderLinesCompanion(')
          ..write('orderId: $orderId, ')
          ..write('position: $position, ')
          ..write('lineId: $lineId, ')
          ..write('addedAtCounter: $addedAtCounter, ')
          ..write('addedAtDevice: $addedAtDevice, ')
          ..write('productId: $productId, ')
          ..write('description: $description, ')
          ..write('quantity: $quantity, ')
          ..write('unitPriceCents: $unitPriceCents, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxTable extends Outbox with TableInfo<$OutboxTable, OutboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _orderIdMeta =
      const VerificationMeta('orderId');
  @override
  late final GeneratedColumn<String> orderId = GeneratedColumn<String>(
      'order_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _attemptsMeta =
      const VerificationMeta('attempts');
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
      'attempts', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant<int>(0));
  static const VerificationMeta _nextAttemptAtMeta =
      const VerificationMeta('nextAttemptAt');
  @override
  late final GeneratedColumn<int> nextAttemptAt = GeneratedColumn<int>(
      'next_attempt_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _lastErrorMeta =
      const VerificationMeta('lastError');
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
      'last_error', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, orderId, createdAt, attempts, nextAttemptAt, lastError];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox';
  @override
  VerificationContext validateIntegrity(Insertable<OutboxRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('order_id')) {
      context.handle(_orderIdMeta,
          orderId.isAcceptableOrUnknown(data['order_id']!, _orderIdMeta));
    } else if (isInserting) {
      context.missing(_orderIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(_attemptsMeta,
          attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta));
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
          _nextAttemptAtMeta,
          nextAttemptAt.isAcceptableOrUnknown(
              data['next_attempt_at']!, _nextAttemptAtMeta));
    }
    if (data.containsKey('last_error')) {
      context.handle(_lastErrorMeta,
          lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      orderId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}order_id'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      attempts: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}attempts'])!,
      nextAttemptAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}next_attempt_at']),
      lastError: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_error']),
    );
  }

  @override
  $OutboxTable createAlias(String alias) {
    return $OutboxTable(attachedDatabase, alias);
  }
}

class OutboxRow extends DataClass implements Insertable<OutboxRow> {
  final String id;
  final String orderId;
  final int createdAt;
  final int attempts;
  final int? nextAttemptAt;
  final String? lastError;
  const OutboxRow(
      {required this.id,
      required this.orderId,
      required this.createdAt,
      required this.attempts,
      this.nextAttemptAt,
      this.lastError});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['order_id'] = Variable<String>(orderId);
    map['created_at'] = Variable<int>(createdAt);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<int>(nextAttemptAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  OutboxCompanion toCompanion(bool nullToAbsent) {
    return OutboxCompanion(
      id: Value(id),
      orderId: Value(orderId),
      createdAt: Value(createdAt),
      attempts: Value(attempts),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory OutboxRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxRow(
      id: serializer.fromJson<String>(json['id']),
      orderId: serializer.fromJson<String>(json['orderId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAt: serializer.fromJson<int?>(json['nextAttemptAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'orderId': serializer.toJson<String>(orderId),
      'createdAt': serializer.toJson<int>(createdAt),
      'attempts': serializer.toJson<int>(attempts),
      'nextAttemptAt': serializer.toJson<int?>(nextAttemptAt),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  OutboxRow copyWith(
          {String? id,
          String? orderId,
          int? createdAt,
          int? attempts,
          Value<int?> nextAttemptAt = const Value.absent(),
          Value<String?> lastError = const Value.absent()}) =>
      OutboxRow(
        id: id ?? this.id,
        orderId: orderId ?? this.orderId,
        createdAt: createdAt ?? this.createdAt,
        attempts: attempts ?? this.attempts,
        nextAttemptAt:
            nextAttemptAt.present ? nextAttemptAt.value : this.nextAttemptAt,
        lastError: lastError.present ? lastError.value : this.lastError,
      );
  OutboxRow copyWithCompanion(OutboxCompanion data) {
    return OutboxRow(
      id: data.id.present ? data.id.value : this.id,
      orderId: data.orderId.present ? data.orderId.value : this.orderId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxRow(')
          ..write('id: $id, ')
          ..write('orderId: $orderId, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, orderId, createdAt, attempts, nextAttemptAt, lastError);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxRow &&
          other.id == this.id &&
          other.orderId == this.orderId &&
          other.createdAt == this.createdAt &&
          other.attempts == this.attempts &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.lastError == this.lastError);
}

class OutboxCompanion extends UpdateCompanion<OutboxRow> {
  final Value<String> id;
  final Value<String> orderId;
  final Value<int> createdAt;
  final Value<int> attempts;
  final Value<int?> nextAttemptAt;
  final Value<String?> lastError;
  final Value<int> rowid;
  const OutboxCompanion({
    this.id = const Value.absent(),
    this.orderId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxCompanion.insert({
    required String id,
    required String orderId,
    required int createdAt,
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        orderId = Value(orderId),
        createdAt = Value(createdAt);
  static Insertable<OutboxRow> custom({
    Expression<String>? id,
    Expression<String>? orderId,
    Expression<int>? createdAt,
    Expression<int>? attempts,
    Expression<int>? nextAttemptAt,
    Expression<String>? lastError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orderId != null) 'order_id': orderId,
      if (createdAt != null) 'created_at': createdAt,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (lastError != null) 'last_error': lastError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboxCompanion copyWith(
      {Value<String>? id,
      Value<String>? orderId,
      Value<int>? createdAt,
      Value<int>? attempts,
      Value<int?>? nextAttemptAt,
      Value<String?>? lastError,
      Value<int>? rowid}) {
    return OutboxCompanion(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      createdAt: createdAt ?? this.createdAt,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastError: lastError ?? this.lastError,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (orderId.present) {
      map['order_id'] = Variable<String>(orderId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<int>(nextAttemptAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxCompanion(')
          ..write('id: $id, ')
          ..write('orderId: $orderId, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ConflictsTable extends Conflicts
    with TableInfo<$ConflictsTable, ConflictRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConflictsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _orderIdMeta =
      const VerificationMeta('orderId');
  @override
  late final GeneratedColumn<String> orderId = GeneratedColumn<String>(
      'order_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _mineMeta = const VerificationMeta('mine');
  @override
  late final GeneratedColumn<String> mine = GeneratedColumn<String>(
      'mine', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _theirsMeta = const VerificationMeta('theirs');
  @override
  late final GeneratedColumn<String> theirs = GeneratedColumn<String>(
      'theirs', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
      'reason', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _detectedAtMeta =
      const VerificationMeta('detectedAt');
  @override
  late final GeneratedColumn<int> detectedAt = GeneratedColumn<int>(
      'detected_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, orderId, mine, theirs, reason, detectedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conflicts';
  @override
  VerificationContext validateIntegrity(Insertable<ConflictRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('order_id')) {
      context.handle(_orderIdMeta,
          orderId.isAcceptableOrUnknown(data['order_id']!, _orderIdMeta));
    } else if (isInserting) {
      context.missing(_orderIdMeta);
    }
    if (data.containsKey('mine')) {
      context.handle(
          _mineMeta, mine.isAcceptableOrUnknown(data['mine']!, _mineMeta));
    } else if (isInserting) {
      context.missing(_mineMeta);
    }
    if (data.containsKey('theirs')) {
      context.handle(_theirsMeta,
          theirs.isAcceptableOrUnknown(data['theirs']!, _theirsMeta));
    } else if (isInserting) {
      context.missing(_theirsMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(_reasonMeta,
          reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta));
    } else if (isInserting) {
      context.missing(_reasonMeta);
    }
    if (data.containsKey('detected_at')) {
      context.handle(
          _detectedAtMeta,
          detectedAt.isAcceptableOrUnknown(
              data['detected_at']!, _detectedAtMeta));
    } else if (isInserting) {
      context.missing(_detectedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ConflictRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConflictRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      orderId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}order_id'])!,
      mine: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}mine'])!,
      theirs: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}theirs'])!,
      reason: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}reason'])!,
      detectedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}detected_at'])!,
    );
  }

  @override
  $ConflictsTable createAlias(String alias) {
    return $ConflictsTable(attachedDatabase, alias);
  }
}

class ConflictRow extends DataClass implements Insertable<ConflictRow> {
  final String id;
  final String orderId;

  /// La versione locale, serializzata.
  final String mine;

  /// La versione arrivata dall'altro dispositivo, serializzata.
  final String theirs;
  final String reason;
  final int detectedAt;
  const ConflictRow(
      {required this.id,
      required this.orderId,
      required this.mine,
      required this.theirs,
      required this.reason,
      required this.detectedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['order_id'] = Variable<String>(orderId);
    map['mine'] = Variable<String>(mine);
    map['theirs'] = Variable<String>(theirs);
    map['reason'] = Variable<String>(reason);
    map['detected_at'] = Variable<int>(detectedAt);
    return map;
  }

  ConflictsCompanion toCompanion(bool nullToAbsent) {
    return ConflictsCompanion(
      id: Value(id),
      orderId: Value(orderId),
      mine: Value(mine),
      theirs: Value(theirs),
      reason: Value(reason),
      detectedAt: Value(detectedAt),
    );
  }

  factory ConflictRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConflictRow(
      id: serializer.fromJson<String>(json['id']),
      orderId: serializer.fromJson<String>(json['orderId']),
      mine: serializer.fromJson<String>(json['mine']),
      theirs: serializer.fromJson<String>(json['theirs']),
      reason: serializer.fromJson<String>(json['reason']),
      detectedAt: serializer.fromJson<int>(json['detectedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'orderId': serializer.toJson<String>(orderId),
      'mine': serializer.toJson<String>(mine),
      'theirs': serializer.toJson<String>(theirs),
      'reason': serializer.toJson<String>(reason),
      'detectedAt': serializer.toJson<int>(detectedAt),
    };
  }

  ConflictRow copyWith(
          {String? id,
          String? orderId,
          String? mine,
          String? theirs,
          String? reason,
          int? detectedAt}) =>
      ConflictRow(
        id: id ?? this.id,
        orderId: orderId ?? this.orderId,
        mine: mine ?? this.mine,
        theirs: theirs ?? this.theirs,
        reason: reason ?? this.reason,
        detectedAt: detectedAt ?? this.detectedAt,
      );
  ConflictRow copyWithCompanion(ConflictsCompanion data) {
    return ConflictRow(
      id: data.id.present ? data.id.value : this.id,
      orderId: data.orderId.present ? data.orderId.value : this.orderId,
      mine: data.mine.present ? data.mine.value : this.mine,
      theirs: data.theirs.present ? data.theirs.value : this.theirs,
      reason: data.reason.present ? data.reason.value : this.reason,
      detectedAt:
          data.detectedAt.present ? data.detectedAt.value : this.detectedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConflictRow(')
          ..write('id: $id, ')
          ..write('orderId: $orderId, ')
          ..write('mine: $mine, ')
          ..write('theirs: $theirs, ')
          ..write('reason: $reason, ')
          ..write('detectedAt: $detectedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, orderId, mine, theirs, reason, detectedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConflictRow &&
          other.id == this.id &&
          other.orderId == this.orderId &&
          other.mine == this.mine &&
          other.theirs == this.theirs &&
          other.reason == this.reason &&
          other.detectedAt == this.detectedAt);
}

class ConflictsCompanion extends UpdateCompanion<ConflictRow> {
  final Value<String> id;
  final Value<String> orderId;
  final Value<String> mine;
  final Value<String> theirs;
  final Value<String> reason;
  final Value<int> detectedAt;
  final Value<int> rowid;
  const ConflictsCompanion({
    this.id = const Value.absent(),
    this.orderId = const Value.absent(),
    this.mine = const Value.absent(),
    this.theirs = const Value.absent(),
    this.reason = const Value.absent(),
    this.detectedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConflictsCompanion.insert({
    required String id,
    required String orderId,
    required String mine,
    required String theirs,
    required String reason,
    required int detectedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        orderId = Value(orderId),
        mine = Value(mine),
        theirs = Value(theirs),
        reason = Value(reason),
        detectedAt = Value(detectedAt);
  static Insertable<ConflictRow> custom({
    Expression<String>? id,
    Expression<String>? orderId,
    Expression<String>? mine,
    Expression<String>? theirs,
    Expression<String>? reason,
    Expression<int>? detectedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orderId != null) 'order_id': orderId,
      if (mine != null) 'mine': mine,
      if (theirs != null) 'theirs': theirs,
      if (reason != null) 'reason': reason,
      if (detectedAt != null) 'detected_at': detectedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConflictsCompanion copyWith(
      {Value<String>? id,
      Value<String>? orderId,
      Value<String>? mine,
      Value<String>? theirs,
      Value<String>? reason,
      Value<int>? detectedAt,
      Value<int>? rowid}) {
    return ConflictsCompanion(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      mine: mine ?? this.mine,
      theirs: theirs ?? this.theirs,
      reason: reason ?? this.reason,
      detectedAt: detectedAt ?? this.detectedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (orderId.present) {
      map['order_id'] = Variable<String>(orderId.value);
    }
    if (mine.present) {
      map['mine'] = Variable<String>(mine.value);
    }
    if (theirs.present) {
      map['theirs'] = Variable<String>(theirs.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (detectedAt.present) {
      map['detected_at'] = Variable<int>(detectedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConflictsCompanion(')
          ..write('id: $id, ')
          ..write('orderId: $orderId, ')
          ..write('mine: $mine, ')
          ..write('theirs: $theirs, ')
          ..write('reason: $reason, ')
          ..write('detectedAt: $detectedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DeviceIdentityTable extends DeviceIdentity
    with TableInfo<$DeviceIdentityTable, DeviceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DeviceIdentityTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _deviceIdMeta =
      const VerificationMeta('deviceId');
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
      'device_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _counterMeta =
      const VerificationMeta('counter');
  @override
  late final GeneratedColumn<int> counter = GeneratedColumn<int>(
      'counter', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant<int>(0));
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
      'role', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant<String>('standalone'));
  static const VerificationMeta _primaryHostMeta =
      const VerificationMeta('primaryHost');
  @override
  late final GeneratedColumn<String> primaryHost = GeneratedColumn<String>(
      'primary_host', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant<String>(''));
  static const VerificationMeta _primaryPortMeta =
      const VerificationMeta('primaryPort');
  @override
  late final GeneratedColumn<int> primaryPort = GeneratedColumn<int>(
      'primary_port', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant<int>(53170));
  @override
  List<GeneratedColumn> get $columns =>
      [id, deviceId, counter, role, primaryHost, primaryPort];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'device_identity';
  @override
  VerificationContext validateIntegrity(Insertable<DeviceRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('device_id')) {
      context.handle(_deviceIdMeta,
          deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta));
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('counter')) {
      context.handle(_counterMeta,
          counter.isAcceptableOrUnknown(data['counter']!, _counterMeta));
    }
    if (data.containsKey('role')) {
      context.handle(
          _roleMeta, role.isAcceptableOrUnknown(data['role']!, _roleMeta));
    }
    if (data.containsKey('primary_host')) {
      context.handle(
          _primaryHostMeta,
          primaryHost.isAcceptableOrUnknown(
              data['primary_host']!, _primaryHostMeta));
    }
    if (data.containsKey('primary_port')) {
      context.handle(
          _primaryPortMeta,
          primaryPort.isAcceptableOrUnknown(
              data['primary_port']!, _primaryPortMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DeviceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeviceRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      deviceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}device_id'])!,
      counter: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}counter'])!,
      role: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}role'])!,
      primaryHost: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}primary_host'])!,
      primaryPort: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}primary_port'])!,
    );
  }

  @override
  $DeviceIdentityTable createAlias(String alias) {
    return $DeviceIdentityTable(attachedDatabase, alias);
  }
}

class DeviceRow extends DataClass implements Insertable<DeviceRow> {
  /// Sempre 1: la riga è una sola e questo lo rende impossibile da sbagliare.
  final int id;
  final String deviceId;
  final int counter;

  /// Che parte fa questo dispositivo in rete locale.
  ///
  /// Sta qui e non in una tabella sua per la stessa ragione del contatore: è
  /// una cassetta a riga singola, e una tabella in più per tre colonne
  /// sarebbe cerimonia. Il valore predefinito non è una comodità — un'app
  /// appena installata deve funzionare senza che nessuno abbia configurato
  /// niente.
  final String role;

  /// Indirizzo del primario, significativo solo per un follower.
  final String primaryHost;

  /// Deve valere quanto `lanPort` in `lan/lan_protocol.dart`.
  ///
  /// Scritto a mano invece di importare la costante perché drift **ricopia
  /// questa espressione nel codice generato**, che non ha quell'import e non
  /// compilerebbe. I due valori sono tenuti allineati da un test, che è il
  /// solo modo per accorgersene se uno dei due cambia.
  final int primaryPort;
  const DeviceRow(
      {required this.id,
      required this.deviceId,
      required this.counter,
      required this.role,
      required this.primaryHost,
      required this.primaryPort});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['device_id'] = Variable<String>(deviceId);
    map['counter'] = Variable<int>(counter);
    map['role'] = Variable<String>(role);
    map['primary_host'] = Variable<String>(primaryHost);
    map['primary_port'] = Variable<int>(primaryPort);
    return map;
  }

  DeviceIdentityCompanion toCompanion(bool nullToAbsent) {
    return DeviceIdentityCompanion(
      id: Value(id),
      deviceId: Value(deviceId),
      counter: Value(counter),
      role: Value(role),
      primaryHost: Value(primaryHost),
      primaryPort: Value(primaryPort),
    );
  }

  factory DeviceRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeviceRow(
      id: serializer.fromJson<int>(json['id']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      counter: serializer.fromJson<int>(json['counter']),
      role: serializer.fromJson<String>(json['role']),
      primaryHost: serializer.fromJson<String>(json['primaryHost']),
      primaryPort: serializer.fromJson<int>(json['primaryPort']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'deviceId': serializer.toJson<String>(deviceId),
      'counter': serializer.toJson<int>(counter),
      'role': serializer.toJson<String>(role),
      'primaryHost': serializer.toJson<String>(primaryHost),
      'primaryPort': serializer.toJson<int>(primaryPort),
    };
  }

  DeviceRow copyWith(
          {int? id,
          String? deviceId,
          int? counter,
          String? role,
          String? primaryHost,
          int? primaryPort}) =>
      DeviceRow(
        id: id ?? this.id,
        deviceId: deviceId ?? this.deviceId,
        counter: counter ?? this.counter,
        role: role ?? this.role,
        primaryHost: primaryHost ?? this.primaryHost,
        primaryPort: primaryPort ?? this.primaryPort,
      );
  DeviceRow copyWithCompanion(DeviceIdentityCompanion data) {
    return DeviceRow(
      id: data.id.present ? data.id.value : this.id,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      counter: data.counter.present ? data.counter.value : this.counter,
      role: data.role.present ? data.role.value : this.role,
      primaryHost:
          data.primaryHost.present ? data.primaryHost.value : this.primaryHost,
      primaryPort:
          data.primaryPort.present ? data.primaryPort.value : this.primaryPort,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeviceRow(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('counter: $counter, ')
          ..write('role: $role, ')
          ..write('primaryHost: $primaryHost, ')
          ..write('primaryPort: $primaryPort')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, deviceId, counter, role, primaryHost, primaryPort);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeviceRow &&
          other.id == this.id &&
          other.deviceId == this.deviceId &&
          other.counter == this.counter &&
          other.role == this.role &&
          other.primaryHost == this.primaryHost &&
          other.primaryPort == this.primaryPort);
}

class DeviceIdentityCompanion extends UpdateCompanion<DeviceRow> {
  final Value<int> id;
  final Value<String> deviceId;
  final Value<int> counter;
  final Value<String> role;
  final Value<String> primaryHost;
  final Value<int> primaryPort;
  const DeviceIdentityCompanion({
    this.id = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.counter = const Value.absent(),
    this.role = const Value.absent(),
    this.primaryHost = const Value.absent(),
    this.primaryPort = const Value.absent(),
  });
  DeviceIdentityCompanion.insert({
    this.id = const Value.absent(),
    required String deviceId,
    this.counter = const Value.absent(),
    this.role = const Value.absent(),
    this.primaryHost = const Value.absent(),
    this.primaryPort = const Value.absent(),
  }) : deviceId = Value(deviceId);
  static Insertable<DeviceRow> custom({
    Expression<int>? id,
    Expression<String>? deviceId,
    Expression<int>? counter,
    Expression<String>? role,
    Expression<String>? primaryHost,
    Expression<int>? primaryPort,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (deviceId != null) 'device_id': deviceId,
      if (counter != null) 'counter': counter,
      if (role != null) 'role': role,
      if (primaryHost != null) 'primary_host': primaryHost,
      if (primaryPort != null) 'primary_port': primaryPort,
    });
  }

  DeviceIdentityCompanion copyWith(
      {Value<int>? id,
      Value<String>? deviceId,
      Value<int>? counter,
      Value<String>? role,
      Value<String>? primaryHost,
      Value<int>? primaryPort}) {
    return DeviceIdentityCompanion(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      counter: counter ?? this.counter,
      role: role ?? this.role,
      primaryHost: primaryHost ?? this.primaryHost,
      primaryPort: primaryPort ?? this.primaryPort,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (counter.present) {
      map['counter'] = Variable<int>(counter.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (primaryHost.present) {
      map['primary_host'] = Variable<String>(primaryHost.value);
    }
    if (primaryPort.present) {
      map['primary_port'] = Variable<int>(primaryPort.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DeviceIdentityCompanion(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('counter: $counter, ')
          ..write('role: $role, ')
          ..write('primaryHost: $primaryHost, ')
          ..write('primaryPort: $primaryPort')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $OrdersTable orders = $OrdersTable(this);
  late final $OrderLinesTable orderLines = $OrderLinesTable(this);
  late final $OutboxTable outbox = $OutboxTable(this);
  late final $ConflictsTable conflicts = $ConflictsTable(this);
  late final $DeviceIdentityTable deviceIdentity = $DeviceIdentityTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [orders, orderLines, outbox, conflicts, deviceIdentity];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules(
        [
          WritePropagation(
            on: TableUpdateQuery.onTableName('orders',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('order_lines', kind: UpdateKind.delete),
            ],
          ),
        ],
      );
}

typedef $$OrdersTableCreateCompanionBuilder = OrdersCompanion Function({
  required String id,
  required int tableNumber,
  required int createdAt,
  required String status,
  Value<String> state,
  Value<int> stateRevisionCounter,
  Value<String> stateRevisionDevice,
  Value<int> rowid,
});
typedef $$OrdersTableUpdateCompanionBuilder = OrdersCompanion Function({
  Value<String> id,
  Value<int> tableNumber,
  Value<int> createdAt,
  Value<String> status,
  Value<String> state,
  Value<int> stateRevisionCounter,
  Value<String> stateRevisionDevice,
  Value<int> rowid,
});

final class $$OrdersTableReferences
    extends BaseReferences<_$AppDatabase, $OrdersTable, OrderRow> {
  $$OrdersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$OrderLinesTable, List<OrderLineRow>>
      _orderLinesRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.orderLines,
              aliasName: 'orders__id__order_lines__order_id');

  $$OrderLinesTableProcessedTableManager get orderLinesRefs {
    final manager = $$OrderLinesTableTableManager($_db, $_db.orderLines)
        .filter((f) => f.orderId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_orderLinesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$OrdersTableFilterComposer
    extends Composer<_$AppDatabase, $OrdersTable> {
  $$OrdersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get tableNumber => $composableBuilder(
      column: $table.tableNumber, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get state => $composableBuilder(
      column: $table.state, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get stateRevisionCounter => $composableBuilder(
      column: $table.stateRevisionCounter,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get stateRevisionDevice => $composableBuilder(
      column: $table.stateRevisionDevice,
      builder: (column) => ColumnFilters(column));

  Expression<bool> orderLinesRefs(
      Expression<bool> Function($$OrderLinesTableFilterComposer f) f) {
    final $$OrderLinesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.orderLines,
        getReferencedColumn: (t) => t.orderId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$OrderLinesTableFilterComposer(
              $db: $db,
              $table: $db.orderLines,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$OrdersTableOrderingComposer
    extends Composer<_$AppDatabase, $OrdersTable> {
  $$OrdersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get tableNumber => $composableBuilder(
      column: $table.tableNumber, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get state => $composableBuilder(
      column: $table.state, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get stateRevisionCounter => $composableBuilder(
      column: $table.stateRevisionCounter,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get stateRevisionDevice => $composableBuilder(
      column: $table.stateRevisionDevice,
      builder: (column) => ColumnOrderings(column));
}

class $$OrdersTableAnnotationComposer
    extends Composer<_$AppDatabase, $OrdersTable> {
  $$OrdersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get tableNumber => $composableBuilder(
      column: $table.tableNumber, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get stateRevisionCounter => $composableBuilder(
      column: $table.stateRevisionCounter, builder: (column) => column);

  GeneratedColumn<String> get stateRevisionDevice => $composableBuilder(
      column: $table.stateRevisionDevice, builder: (column) => column);

  Expression<T> orderLinesRefs<T extends Object>(
      Expression<T> Function($$OrderLinesTableAnnotationComposer a) f) {
    final $$OrderLinesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.orderLines,
        getReferencedColumn: (t) => t.orderId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$OrderLinesTableAnnotationComposer(
              $db: $db,
              $table: $db.orderLines,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$OrdersTableTableManager extends RootTableManager<
    _$AppDatabase,
    $OrdersTable,
    OrderRow,
    $$OrdersTableFilterComposer,
    $$OrdersTableOrderingComposer,
    $$OrdersTableAnnotationComposer,
    $$OrdersTableCreateCompanionBuilder,
    $$OrdersTableUpdateCompanionBuilder,
    (OrderRow, $$OrdersTableReferences),
    OrderRow,
    PrefetchHooks Function({bool orderLinesRefs})> {
  $$OrdersTableTableManager(_$AppDatabase db, $OrdersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OrdersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OrdersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OrdersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<int> tableNumber = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String> state = const Value.absent(),
            Value<int> stateRevisionCounter = const Value.absent(),
            Value<String> stateRevisionDevice = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              OrdersCompanion(
            id: id,
            tableNumber: tableNumber,
            createdAt: createdAt,
            status: status,
            state: state,
            stateRevisionCounter: stateRevisionCounter,
            stateRevisionDevice: stateRevisionDevice,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required int tableNumber,
            required int createdAt,
            required String status,
            Value<String> state = const Value.absent(),
            Value<int> stateRevisionCounter = const Value.absent(),
            Value<String> stateRevisionDevice = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              OrdersCompanion.insert(
            id: id,
            tableNumber: tableNumber,
            createdAt: createdAt,
            status: status,
            state: state,
            stateRevisionCounter: stateRevisionCounter,
            stateRevisionDevice: stateRevisionDevice,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$OrdersTable, OrderRow>(table),
                    $$OrdersTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({orderLinesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (orderLinesRefs) db.orderLines],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (orderLinesRefs)
                    await $_getPrefetchedData<OrderRow, $OrdersTable,
                            OrderLineRow>(
                        currentTable: table,
                        referencedTable:
                            $$OrdersTableReferences._orderLinesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$OrdersTableReferences(db, table, p0)
                                .orderLinesRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.orderId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$OrdersTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $OrdersTable,
    OrderRow,
    $$OrdersTableFilterComposer,
    $$OrdersTableOrderingComposer,
    $$OrdersTableAnnotationComposer,
    $$OrdersTableCreateCompanionBuilder,
    $$OrdersTableUpdateCompanionBuilder,
    (OrderRow, $$OrdersTableReferences),
    OrderRow,
    PrefetchHooks Function({bool orderLinesRefs})>;
typedef $$OrderLinesTableCreateCompanionBuilder = OrderLinesCompanion Function({
  required String orderId,
  required int position,
  Value<String> lineId,
  Value<int> addedAtCounter,
  Value<String> addedAtDevice,
  required String productId,
  required String description,
  required int quantity,
  required int unitPriceCents,
  Value<int> rowid,
});
typedef $$OrderLinesTableUpdateCompanionBuilder = OrderLinesCompanion Function({
  Value<String> orderId,
  Value<int> position,
  Value<String> lineId,
  Value<int> addedAtCounter,
  Value<String> addedAtDevice,
  Value<String> productId,
  Value<String> description,
  Value<int> quantity,
  Value<int> unitPriceCents,
  Value<int> rowid,
});

final class $$OrderLinesTableReferences
    extends BaseReferences<_$AppDatabase, $OrderLinesTable, OrderLineRow> {
  $$OrderLinesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $OrdersTable _orderIdTable(_$AppDatabase db) =>
      db.orders.createAlias('order_lines__order_id__orders__id');

  $$OrdersTableProcessedTableManager get orderId {
    final $_column = $_itemColumn<String>('order_id')!;

    final manager = $$OrdersTableTableManager($_db, $_db.orders)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_orderIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$OrderLinesTableFilterComposer
    extends Composer<_$AppDatabase, $OrderLinesTable> {
  $$OrderLinesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get position => $composableBuilder(
      column: $table.position, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lineId => $composableBuilder(
      column: $table.lineId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get addedAtCounter => $composableBuilder(
      column: $table.addedAtCounter,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get addedAtDevice => $composableBuilder(
      column: $table.addedAtDevice, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get productId => $composableBuilder(
      column: $table.productId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get quantity => $composableBuilder(
      column: $table.quantity, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get unitPriceCents => $composableBuilder(
      column: $table.unitPriceCents,
      builder: (column) => ColumnFilters(column));

  $$OrdersTableFilterComposer get orderId {
    final $$OrdersTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.orderId,
        referencedTable: $db.orders,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$OrdersTableFilterComposer(
              $db: $db,
              $table: $db.orders,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$OrderLinesTableOrderingComposer
    extends Composer<_$AppDatabase, $OrderLinesTable> {
  $$OrderLinesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get position => $composableBuilder(
      column: $table.position, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lineId => $composableBuilder(
      column: $table.lineId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get addedAtCounter => $composableBuilder(
      column: $table.addedAtCounter,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get addedAtDevice => $composableBuilder(
      column: $table.addedAtDevice,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get productId => $composableBuilder(
      column: $table.productId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get quantity => $composableBuilder(
      column: $table.quantity, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get unitPriceCents => $composableBuilder(
      column: $table.unitPriceCents,
      builder: (column) => ColumnOrderings(column));

  $$OrdersTableOrderingComposer get orderId {
    final $$OrdersTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.orderId,
        referencedTable: $db.orders,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$OrdersTableOrderingComposer(
              $db: $db,
              $table: $db.orders,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$OrderLinesTableAnnotationComposer
    extends Composer<_$AppDatabase, $OrderLinesTable> {
  $$OrderLinesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get lineId =>
      $composableBuilder(column: $table.lineId, builder: (column) => column);

  GeneratedColumn<int> get addedAtCounter => $composableBuilder(
      column: $table.addedAtCounter, builder: (column) => column);

  GeneratedColumn<String> get addedAtDevice => $composableBuilder(
      column: $table.addedAtDevice, builder: (column) => column);

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<int> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<int> get unitPriceCents => $composableBuilder(
      column: $table.unitPriceCents, builder: (column) => column);

  $$OrdersTableAnnotationComposer get orderId {
    final $$OrdersTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.orderId,
        referencedTable: $db.orders,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$OrdersTableAnnotationComposer(
              $db: $db,
              $table: $db.orders,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$OrderLinesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $OrderLinesTable,
    OrderLineRow,
    $$OrderLinesTableFilterComposer,
    $$OrderLinesTableOrderingComposer,
    $$OrderLinesTableAnnotationComposer,
    $$OrderLinesTableCreateCompanionBuilder,
    $$OrderLinesTableUpdateCompanionBuilder,
    (OrderLineRow, $$OrderLinesTableReferences),
    OrderLineRow,
    PrefetchHooks Function({bool orderId})> {
  $$OrderLinesTableTableManager(_$AppDatabase db, $OrderLinesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OrderLinesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OrderLinesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OrderLinesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> orderId = const Value.absent(),
            Value<int> position = const Value.absent(),
            Value<String> lineId = const Value.absent(),
            Value<int> addedAtCounter = const Value.absent(),
            Value<String> addedAtDevice = const Value.absent(),
            Value<String> productId = const Value.absent(),
            Value<String> description = const Value.absent(),
            Value<int> quantity = const Value.absent(),
            Value<int> unitPriceCents = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              OrderLinesCompanion(
            orderId: orderId,
            position: position,
            lineId: lineId,
            addedAtCounter: addedAtCounter,
            addedAtDevice: addedAtDevice,
            productId: productId,
            description: description,
            quantity: quantity,
            unitPriceCents: unitPriceCents,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String orderId,
            required int position,
            Value<String> lineId = const Value.absent(),
            Value<int> addedAtCounter = const Value.absent(),
            Value<String> addedAtDevice = const Value.absent(),
            required String productId,
            required String description,
            required int quantity,
            required int unitPriceCents,
            Value<int> rowid = const Value.absent(),
          }) =>
              OrderLinesCompanion.insert(
            orderId: orderId,
            position: position,
            lineId: lineId,
            addedAtCounter: addedAtCounter,
            addedAtDevice: addedAtDevice,
            productId: productId,
            description: description,
            quantity: quantity,
            unitPriceCents: unitPriceCents,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$OrderLinesTable, OrderLineRow>(table),
                    $$OrderLinesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({orderId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (orderId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.orderId,
                    referencedTable:
                        $$OrderLinesTableReferences._orderIdTable(db),
                    referencedColumn:
                        $$OrderLinesTableReferences._orderIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$OrderLinesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $OrderLinesTable,
    OrderLineRow,
    $$OrderLinesTableFilterComposer,
    $$OrderLinesTableOrderingComposer,
    $$OrderLinesTableAnnotationComposer,
    $$OrderLinesTableCreateCompanionBuilder,
    $$OrderLinesTableUpdateCompanionBuilder,
    (OrderLineRow, $$OrderLinesTableReferences),
    OrderLineRow,
    PrefetchHooks Function({bool orderId})>;
typedef $$OutboxTableCreateCompanionBuilder = OutboxCompanion Function({
  required String id,
  required String orderId,
  required int createdAt,
  Value<int> attempts,
  Value<int?> nextAttemptAt,
  Value<String?> lastError,
  Value<int> rowid,
});
typedef $$OutboxTableUpdateCompanionBuilder = OutboxCompanion Function({
  Value<String> id,
  Value<String> orderId,
  Value<int> createdAt,
  Value<int> attempts,
  Value<int?> nextAttemptAt,
  Value<String?> lastError,
  Value<int> rowid,
});

class $$OutboxTableFilterComposer
    extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get orderId => $composableBuilder(
      column: $table.orderId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get attempts => $composableBuilder(
      column: $table.attempts, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get nextAttemptAt => $composableBuilder(
      column: $table.nextAttemptAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastError => $composableBuilder(
      column: $table.lastError, builder: (column) => ColumnFilters(column));
}

class $$OutboxTableOrderingComposer
    extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get orderId => $composableBuilder(
      column: $table.orderId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get attempts => $composableBuilder(
      column: $table.attempts, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get nextAttemptAt => $composableBuilder(
      column: $table.nextAttemptAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastError => $composableBuilder(
      column: $table.lastError, builder: (column) => ColumnOrderings(column));
}

class $$OutboxTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get orderId =>
      $composableBuilder(column: $table.orderId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<int> get nextAttemptAt => $composableBuilder(
      column: $table.nextAttemptAt, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$OutboxTableTableManager extends RootTableManager<
    _$AppDatabase,
    $OutboxTable,
    OutboxRow,
    $$OutboxTableFilterComposer,
    $$OutboxTableOrderingComposer,
    $$OutboxTableAnnotationComposer,
    $$OutboxTableCreateCompanionBuilder,
    $$OutboxTableUpdateCompanionBuilder,
    (OutboxRow, BaseReferences<_$AppDatabase, $OutboxTable, OutboxRow>),
    OutboxRow,
    PrefetchHooks Function()> {
  $$OutboxTableTableManager(_$AppDatabase db, $OutboxTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> orderId = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> attempts = const Value.absent(),
            Value<int?> nextAttemptAt = const Value.absent(),
            Value<String?> lastError = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              OutboxCompanion(
            id: id,
            orderId: orderId,
            createdAt: createdAt,
            attempts: attempts,
            nextAttemptAt: nextAttemptAt,
            lastError: lastError,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String orderId,
            required int createdAt,
            Value<int> attempts = const Value.absent(),
            Value<int?> nextAttemptAt = const Value.absent(),
            Value<String?> lastError = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              OutboxCompanion.insert(
            id: id,
            orderId: orderId,
            createdAt: createdAt,
            attempts: attempts,
            nextAttemptAt: nextAttemptAt,
            lastError: lastError,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$OutboxTable, OutboxRow>(table),
                    BaseReferences<_$AppDatabase, $OutboxTable, OutboxRow>(
                        db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$OutboxTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $OutboxTable,
    OutboxRow,
    $$OutboxTableFilterComposer,
    $$OutboxTableOrderingComposer,
    $$OutboxTableAnnotationComposer,
    $$OutboxTableCreateCompanionBuilder,
    $$OutboxTableUpdateCompanionBuilder,
    (OutboxRow, BaseReferences<_$AppDatabase, $OutboxTable, OutboxRow>),
    OutboxRow,
    PrefetchHooks Function()>;
typedef $$ConflictsTableCreateCompanionBuilder = ConflictsCompanion Function({
  required String id,
  required String orderId,
  required String mine,
  required String theirs,
  required String reason,
  required int detectedAt,
  Value<int> rowid,
});
typedef $$ConflictsTableUpdateCompanionBuilder = ConflictsCompanion Function({
  Value<String> id,
  Value<String> orderId,
  Value<String> mine,
  Value<String> theirs,
  Value<String> reason,
  Value<int> detectedAt,
  Value<int> rowid,
});

class $$ConflictsTableFilterComposer
    extends Composer<_$AppDatabase, $ConflictsTable> {
  $$ConflictsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get orderId => $composableBuilder(
      column: $table.orderId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mine => $composableBuilder(
      column: $table.mine, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get theirs => $composableBuilder(
      column: $table.theirs, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get reason => $composableBuilder(
      column: $table.reason, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get detectedAt => $composableBuilder(
      column: $table.detectedAt, builder: (column) => ColumnFilters(column));
}

class $$ConflictsTableOrderingComposer
    extends Composer<_$AppDatabase, $ConflictsTable> {
  $$ConflictsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get orderId => $composableBuilder(
      column: $table.orderId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mine => $composableBuilder(
      column: $table.mine, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get theirs => $composableBuilder(
      column: $table.theirs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get reason => $composableBuilder(
      column: $table.reason, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get detectedAt => $composableBuilder(
      column: $table.detectedAt, builder: (column) => ColumnOrderings(column));
}

class $$ConflictsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConflictsTable> {
  $$ConflictsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get orderId =>
      $composableBuilder(column: $table.orderId, builder: (column) => column);

  GeneratedColumn<String> get mine =>
      $composableBuilder(column: $table.mine, builder: (column) => column);

  GeneratedColumn<String> get theirs =>
      $composableBuilder(column: $table.theirs, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<int> get detectedAt => $composableBuilder(
      column: $table.detectedAt, builder: (column) => column);
}

class $$ConflictsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ConflictsTable,
    ConflictRow,
    $$ConflictsTableFilterComposer,
    $$ConflictsTableOrderingComposer,
    $$ConflictsTableAnnotationComposer,
    $$ConflictsTableCreateCompanionBuilder,
    $$ConflictsTableUpdateCompanionBuilder,
    (ConflictRow, BaseReferences<_$AppDatabase, $ConflictsTable, ConflictRow>),
    ConflictRow,
    PrefetchHooks Function()> {
  $$ConflictsTableTableManager(_$AppDatabase db, $ConflictsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConflictsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConflictsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConflictsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> orderId = const Value.absent(),
            Value<String> mine = const Value.absent(),
            Value<String> theirs = const Value.absent(),
            Value<String> reason = const Value.absent(),
            Value<int> detectedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ConflictsCompanion(
            id: id,
            orderId: orderId,
            mine: mine,
            theirs: theirs,
            reason: reason,
            detectedAt: detectedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String orderId,
            required String mine,
            required String theirs,
            required String reason,
            required int detectedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              ConflictsCompanion.insert(
            id: id,
            orderId: orderId,
            mine: mine,
            theirs: theirs,
            reason: reason,
            detectedAt: detectedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$ConflictsTable, ConflictRow>(table),
                    BaseReferences<_$AppDatabase, $ConflictsTable, ConflictRow>(
                        db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ConflictsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ConflictsTable,
    ConflictRow,
    $$ConflictsTableFilterComposer,
    $$ConflictsTableOrderingComposer,
    $$ConflictsTableAnnotationComposer,
    $$ConflictsTableCreateCompanionBuilder,
    $$ConflictsTableUpdateCompanionBuilder,
    (ConflictRow, BaseReferences<_$AppDatabase, $ConflictsTable, ConflictRow>),
    ConflictRow,
    PrefetchHooks Function()>;
typedef $$DeviceIdentityTableCreateCompanionBuilder = DeviceIdentityCompanion
    Function({
  Value<int> id,
  required String deviceId,
  Value<int> counter,
  Value<String> role,
  Value<String> primaryHost,
  Value<int> primaryPort,
});
typedef $$DeviceIdentityTableUpdateCompanionBuilder = DeviceIdentityCompanion
    Function({
  Value<int> id,
  Value<String> deviceId,
  Value<int> counter,
  Value<String> role,
  Value<String> primaryHost,
  Value<int> primaryPort,
});

class $$DeviceIdentityTableFilterComposer
    extends Composer<_$AppDatabase, $DeviceIdentityTable> {
  $$DeviceIdentityTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get counter => $composableBuilder(
      column: $table.counter, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get primaryHost => $composableBuilder(
      column: $table.primaryHost, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get primaryPort => $composableBuilder(
      column: $table.primaryPort, builder: (column) => ColumnFilters(column));
}

class $$DeviceIdentityTableOrderingComposer
    extends Composer<_$AppDatabase, $DeviceIdentityTable> {
  $$DeviceIdentityTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get counter => $composableBuilder(
      column: $table.counter, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get primaryHost => $composableBuilder(
      column: $table.primaryHost, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get primaryPort => $composableBuilder(
      column: $table.primaryPort, builder: (column) => ColumnOrderings(column));
}

class $$DeviceIdentityTableAnnotationComposer
    extends Composer<_$AppDatabase, $DeviceIdentityTable> {
  $$DeviceIdentityTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get counter =>
      $composableBuilder(column: $table.counter, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get primaryHost => $composableBuilder(
      column: $table.primaryHost, builder: (column) => column);

  GeneratedColumn<int> get primaryPort => $composableBuilder(
      column: $table.primaryPort, builder: (column) => column);
}

class $$DeviceIdentityTableTableManager extends RootTableManager<
    _$AppDatabase,
    $DeviceIdentityTable,
    DeviceRow,
    $$DeviceIdentityTableFilterComposer,
    $$DeviceIdentityTableOrderingComposer,
    $$DeviceIdentityTableAnnotationComposer,
    $$DeviceIdentityTableCreateCompanionBuilder,
    $$DeviceIdentityTableUpdateCompanionBuilder,
    (DeviceRow, BaseReferences<_$AppDatabase, $DeviceIdentityTable, DeviceRow>),
    DeviceRow,
    PrefetchHooks Function()> {
  $$DeviceIdentityTableTableManager(
      _$AppDatabase db, $DeviceIdentityTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DeviceIdentityTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DeviceIdentityTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DeviceIdentityTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> deviceId = const Value.absent(),
            Value<int> counter = const Value.absent(),
            Value<String> role = const Value.absent(),
            Value<String> primaryHost = const Value.absent(),
            Value<int> primaryPort = const Value.absent(),
          }) =>
              DeviceIdentityCompanion(
            id: id,
            deviceId: deviceId,
            counter: counter,
            role: role,
            primaryHost: primaryHost,
            primaryPort: primaryPort,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String deviceId,
            Value<int> counter = const Value.absent(),
            Value<String> role = const Value.absent(),
            Value<String> primaryHost = const Value.absent(),
            Value<int> primaryPort = const Value.absent(),
          }) =>
              DeviceIdentityCompanion.insert(
            id: id,
            deviceId: deviceId,
            counter: counter,
            role: role,
            primaryHost: primaryHost,
            primaryPort: primaryPort,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$DeviceIdentityTable, DeviceRow>(table),
                    BaseReferences<_$AppDatabase, $DeviceIdentityTable,
                        DeviceRow>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$DeviceIdentityTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $DeviceIdentityTable,
    DeviceRow,
    $$DeviceIdentityTableFilterComposer,
    $$DeviceIdentityTableOrderingComposer,
    $$DeviceIdentityTableAnnotationComposer,
    $$DeviceIdentityTableCreateCompanionBuilder,
    $$DeviceIdentityTableUpdateCompanionBuilder,
    (DeviceRow, BaseReferences<_$AppDatabase, $DeviceIdentityTable, DeviceRow>),
    DeviceRow,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$OrdersTableTableManager get orders =>
      $$OrdersTableTableManager(_db, _db.orders);
  $$OrderLinesTableTableManager get orderLines =>
      $$OrderLinesTableTableManager(_db, _db.orderLines);
  $$OutboxTableTableManager get outbox =>
      $$OutboxTableTableManager(_db, _db.outbox);
  $$ConflictsTableTableManager get conflicts =>
      $$ConflictsTableTableManager(_db, _db.conflicts);
  $$DeviceIdentityTableTableManager get deviceIdentity =>
      $$DeviceIdentityTableTableManager(_db, _db.deviceIdentity);
}
