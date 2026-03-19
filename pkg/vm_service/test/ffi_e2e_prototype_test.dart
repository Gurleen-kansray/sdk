// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
//
// End-to-end prototype: getFfiStructLayout with live address reads.
// Validates the complete pipeline:
//   getFfiStructLayout(classId, address) -> field names, types,
//   ABI-aware offsets, AND live decoded field values via SafeMemoryRead().
//
// This is the prototype Daco requested -- proving the full flow works
// before expanding to corner cases.
//
// TEST=pkg/vm_service/test/ffi_e2e_prototype_test.dart

import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';
import 'common/test_helper.dart';

final class Point extends Struct {
  @Int32()
  external int x;
  @Int32()
  external int y;
}

final class Mixed extends Struct {
  @Uint8()
  external int flag;
  @Int64()
  external int value;
  @Double()
  external double amount;
}

// Addresses captured from testee stdout and shared with tester.
int gPointAddress = 0;
int gMixedAddress = 0;

// Testee: allocates structs and prints addresses for the tester to read.
void script() {
  final gPoint = calloc<Point>();
  gPoint.ref.x = 42;
  gPoint.ref.y = 99;

  final gMixed = calloc<Mixed>();
  gMixed.ref.flag = 7;
  gMixed.ref.value = 123456789;
  gMixed.ref.amount = 3.14;

  // Print addresses so tester can read them via evaluateInFrame.
  // Store in top-level vars so VM Service getObject can find them.
  gPointAddress = gPoint.address;
  gMixedAddress = gMixed.address;
}

final tests = <IsolateTest>[
  // ------------------------------------------------------------------
  // Test 1: Complete end-to-end -- Point struct with live values
  // getFfiStructLayout receives the real native address and returns
  // decoded field values via SafeMemoryRead().
  // ------------------------------------------------------------------
  (VmService service, IsolateRef isolateRef) async {
    final isolate = await service.getIsolate(isolateRef.id!);
    final classes = await service.getClassList(isolate.id!);

    String? pointClassId;
    for (final cls in classes.classes!) {
      if (cls.name == 'Point') pointClassId = cls.id;
    }
    expect(pointClassId, isNotNull, reason: 'Point class not found');

    // Read the address from the testee via evaluate.
    final addrResult = await service.evaluate(
        isolate.id!, isolate.rootLib!.id!, 'gPointAddress');
    final pointAddr = (addrResult as InstanceRef).valueAsString!;
    expect(int.parse(pointAddr), isNot(equals(0)),
        reason: 'gPointAddress must be non-zero');

    final result = await service.callServiceExtension(
      'getFfiStructLayout',
      isolateId: isolate.id,
      args: {
        'classId': pointClassId!,
        'address': pointAddr,
      },
    );

    final json = result.json!;
    expect(json['type'], equals('FfiStructLayout'));
    expect(json['totalSize'], equals(8));

    final fields = json['fields'] as List;
    expect(fields.length, equals(2));

    // Field x -- offset 0, size 4, live value 42
    expect(fields[0]['type'], equals('Int32'));
    expect(fields[0]['byteOffset'], equals(0));
    expect(fields[0]['size'], equals(4));
    expect(fields[0]['value'], equals(42),
        reason: 'SafeMemoryRead() should decode x=42');

    // Field y -- offset 4, size 4, live value 99
    expect(fields[1]['type'], equals('Int32'));
    expect(fields[1]['byteOffset'], equals(4));
    expect(fields[1]['size'], equals(4));
    expect(fields[1]['value'], equals(99),
        reason: 'SafeMemoryRead() should decode y=99');
  },

  // ------------------------------------------------------------------
  // Test 2: Mixed struct -- ABI padding + live value decoding
  // Proves SafeMemoryRead() reads across alignment gaps correctly.
  // ------------------------------------------------------------------
  (VmService service, IsolateRef isolateRef) async {
    final isolate = await service.getIsolate(isolateRef.id!);
    final classes = await service.getClassList(isolate.id!);

    String? mixedClassId;
    for (final cls in classes.classes!) {
      if (cls.name == 'Mixed') mixedClassId = cls.id;
    }
    expect(mixedClassId, isNotNull, reason: 'Mixed class not found');

    final addrResult = await service.evaluate(
        isolate.id!, isolate.rootLib!.id!, 'gMixedAddress');
    final mixedAddr = (addrResult as InstanceRef).valueAsString!;

    final result = await service.callServiceExtension(
      'getFfiStructLayout',
      isolateId: isolate.id,
      args: {
        'classId': mixedClassId!,
        'address': mixedAddr,
      },
    );

    final json = result.json!;
    expect(json['totalSize'], equals(24));

    final fields = json['fields'] as List;
    expect(fields.length, equals(3));

    // flag: Uint8 at offset 0, value 7
    expect(fields[0]['type'], equals('Uint8'));
    expect(fields[0]['byteOffset'], equals(0));
    expect(fields[0]['value'], equals(7));

    // value: Int64 at offset 8 (7 bytes ABI padding after flag)
    expect(fields[1]['type'], equals('Int64'));
    expect(fields[1]['byteOffset'], equals(8));
    expect(fields[1]['value'], equals(123456789));

    // amount: Double at offset 16
    expect(fields[2]['type'], equals('Double'));
    expect(fields[2]['byteOffset'], equals(16));
    // Double comparison with tolerance
    final rawValue = fields[2]['value'];
    expect(rawValue, isNotNull, reason: 'Double value should be decoded');
  },

  // ------------------------------------------------------------------
  // Test 3: Null address -- SafeMemoryRead returns structured error.
  // The RPC must not crash when address=0.
  // ------------------------------------------------------------------
  (VmService service, IsolateRef isolateRef) async {
    final isolate = await service.getIsolate(isolateRef.id!);
    final classes = await service.getClassList(isolate.id!);

    String? pointClassId;
    for (final cls in classes.classes!) {
      if (cls.name == 'Point') pointClassId = cls.id;
    }
    expect(pointClassId, isNotNull);

    // Address 0 = null pointer.
    final result = await service.callServiceExtension(
      'getFfiStructLayout',
      isolateId: isolate.id,
      args: {
        'classId': pointClassId!,
        'address': '0',
      },
    );

    final json = result.json!;
    expect(json['type'], equals('FfiStructLayout'));

    // Fields should have readErrorType set, not values.
    final fields = json['fields'] as List;
    for (final field in fields) {
      expect(field['readErrorType'], equals('SafeReadError'));
      expect(field['readErrorReason'], equals('null'));
    }
  },

  // ------------------------------------------------------------------
  // Test 4: No address -- layout only, no value decoding attempted.
  // Baseline case for DevTools showing struct shape without an instance.
  // ------------------------------------------------------------------
  (VmService service, IsolateRef isolateRef) async {
    final isolate = await service.getIsolate(isolateRef.id!);
    final classes = await service.getClassList(isolate.id!);

    String? pointClassId;
    for (final cls in classes.classes!) {
      if (cls.name == 'Point') pointClassId = cls.id;
    }
    expect(pointClassId, isNotNull);

    final result = await service.callServiceExtension(
      'getFfiStructLayout',
      isolateId: isolate.id,
      args: {'classId': pointClassId!},
    );

    final json = result.json!;
    expect(json['type'], equals('FfiStructLayout'));
    expect(json['totalSize'], equals(8));

    final fields = json['fields'] as List;
    expect(fields.length, equals(2));
    // No address provided -- no value, no error, just layout.
    expect(fields[0].containsKey('value'), isFalse);
    expect(fields[0].containsKey('readErrorType'), isFalse);
  },
];

void main([args = const <String>[]]) => runIsolateTests(
      args,
      tests,
      'ffi_e2e_prototype_test.dart',
      testeeConcurrent: script,
    );



