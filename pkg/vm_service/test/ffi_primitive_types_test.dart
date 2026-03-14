// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';
import 'common/test_helper.dart';

final class PrimitiveStruct extends Struct {
  @Int8()
  external int f1;

  @Int16()
  external int f2;

  @Int32()
  external int f3;

  @Int64()
  external int f4;

  @Uint8()
  external int f5;

  @Uint16()
  external int f6;

  @Uint32()
  external int f7;

  @Uint64()
  external int f8;

  @Float()
  external double f9;

  @Double()
  external double f10;

  @Bool()
  external bool f11;
}

late Pointer<PrimitiveStruct> primitivePtr;

void script() {
  primitivePtr = calloc<PrimitiveStruct>();
  primitivePtr.ref.f1 = -10;
  primitivePtr.ref.f2 = -500;
  primitivePtr.ref.f3 = -70000;
  primitivePtr.ref.f4 = -1000000;
  primitivePtr.ref.f5 = 200;
  primitivePtr.ref.f6 = 60000;
  primitivePtr.ref.f7 = 3000000;
  primitivePtr.ref.f8 = 9000000;
  primitivePtr.ref.f9 = 3.14;
  primitivePtr.ref.f10 = 2.718;
  primitivePtr.ref.f11 = true;
  print('primitive_struct_address=${primitivePtr.address}');
}

final tests = <IsolateTest>[
  (VmService service, IsolateRef isolateRef) async {
    final isolate = await service.getIsolate(isolateRef.id!);

    final classes = await service.getClassList(isolate.id!);
    String? classId;
    for (final cls in classes.classes!) {
      if (cls.name == 'PrimitiveStruct') classId = cls.id;
    }
    expect(classId, isNotNull, reason: 'PrimitiveStruct class not found');

    final addrResult = await service.evaluate(
      isolate.id!,
      isolate.rootLib!.id!,
      'primitivePtr.address',
    );
    expect(addrResult, isA<InstanceRef>());
    final address = (addrResult as InstanceRef).valueAsString!;

    final result = await service.callServiceExtension(
      'getFfiStructLayout',
      isolateId: isolate.id,
      args: {'classId': classId!, 'address': address},
    );
    final json = result.json!;
    expect(json['type'], equals('FfiStructLayout'));

    final fields = json['fields'] as List;
    expect(fields.length, equals(11));

    // Int8
    expect(fields[0]['type'], equals('Int8'));
    expect(fields[0]['value'], equals(-10));

    // Int16
    expect(fields[1]['type'], equals('Int16'));
    expect(fields[1]['value'], equals(-500));

    // Int32
    expect(fields[2]['type'], equals('Int32'));
    expect(fields[2]['value'], equals(-70000));

    // Int64
    expect(fields[3]['type'], equals('Int64'));
    expect(fields[3]['value'], equals(-1000000));

    // Uint8
    expect(fields[4]['type'], equals('Uint8'));
    expect(fields[4]['value'], equals(200));

    // Uint16
    expect(fields[5]['type'], equals('Uint16'));
    expect(fields[5]['value'], equals(60000));

    // Uint32
    expect(fields[6]['type'], equals('Uint32'));
    expect(fields[6]['value'], equals(3000000));

    // Uint64
    expect(fields[7]['type'], equals('Uint64'));
    expect(fields[7]['value'], equals(9000000));

    // Float — returned as formatted string from AddPropertyF
    expect(fields[8]['type'], equals('Float'));
    final floatVal = double.parse(fields[8]['value'] as String);
    expect(floatVal, closeTo(3.14, 0.001));

    // Double — returned as formatted string from AddPropertyF
    expect(fields[9]['type'], equals('Double'));
    final doubleVal = double.parse(fields[9]['value'] as String);
    expect(doubleVal, closeTo(2.718, 0.0001));

    // Bool
    expect(fields[10]['type'], equals('Bool'));
    expect(fields[10]['value'], equals(true));
  },
];

void main([args = const <String>[]]) => runIsolateTests(
  args,
  tests,
  'ffi_primitive_types_test.dart',
  testeeConcurrent: script,
);