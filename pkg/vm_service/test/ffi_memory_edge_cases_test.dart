// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';
import 'common/test_helper.dart';

final class EdgeStruct extends Struct {
  @Int32()
  external int a;

  @Int32()
  external int b;
}

late Pointer<EdgeStruct> validPtr;
late Pointer<Uint8> largeBufferPtr;
late int largeBufferAddress;

void script() {
  validPtr = calloc<EdgeStruct>();
  validPtr.ref.a = 111;
  validPtr.ref.b = 222;

  // Raw buffer larger than one memory page (4096 bytes)
  largeBufferPtr = calloc<Uint8>(8192);
  largeBufferAddress = largeBufferPtr.address;
  // Write 42 as little-endian Int32 at start of buffer
  largeBufferPtr[0] = 42;
  largeBufferPtr[1] = 0;
  largeBufferPtr[2] = 0;
  largeBufferPtr[3] = 0;
  // Second Int32 at offset 4
  largeBufferPtr[4] = 99;
  largeBufferPtr[5] = 0;
  largeBufferPtr[6] = 0;
  largeBufferPtr[7] = 0;

  print('edge_struct_address=${validPtr.address}');
  print('large_buffer_address=${largeBufferAddress}');
}

final tests = <IsolateTest>[
  (VmService service, IsolateRef isolateRef) async {
    final isolate = await service.getIsolate(isolateRef.id!);

    // Find EdgeStruct class ID
    final classes = await service.getClassList(isolate.id!);
    String? edgeClassId;
    for (final cls in classes.classes!) {
      if (cls.name == 'EdgeStruct') edgeClassId = cls.id;
    }
    expect(edgeClassId, isNotNull, reason: 'EdgeStruct class not found');

    // Get real addresses
    final edgeAddrResult = await service.evaluate(
      isolate.id!,
      isolate.rootLib!.id!,
      'validPtr.address',
    );
    expect(edgeAddrResult, isA<InstanceRef>());
    final edgeAddress = (edgeAddrResult as InstanceRef).valueAsString!;

    final largeAddrResult = await service.evaluate(
      isolate.id!,
      isolate.rootLib!.id!,
      'largeBufferAddress',
    );
    expect(largeAddrResult, isA<InstanceRef>());
    final largeAddress = (largeAddrResult as InstanceRef).valueAsString!;

    // Test 1: valid address — correct values
    final validResult = await service.callServiceExtension(
      'getFfiStructLayout',
      isolateId: isolate.id,
      args: {'classId': edgeClassId!, 'address': edgeAddress},
    );
    final validJson = validResult.json!;
    expect(validJson['fields'][0]['value'], equals(111));
    expect(validJson['fields'][1]['value'], equals(222));

    // Test 2: null address — structured SafeReadError with reason "null"
    final nullResult = await service.callServiceExtension(
      'getFfiStructLayout',
      isolateId: isolate.id,
      args: {'classId': edgeClassId, 'address': '0'},
    );
    final nullField0 = nullResult.json!['fields'][0];
    expect(nullField0['readErrorType'], equals('SafeReadError'));
    expect(nullField0['readErrorReason'], equals('null'));
    expect(nullField0['readErrorAddress'], equals('0'));

    // Test 3: unmapped address — structured SafeReadError with reason "unmapped"
    final unmappedResult = await service.callServiceExtension(
      'getFfiStructLayout',
      isolateId: isolate.id,
      args: {'classId': edgeClassId, 'address': '0xDEADBEEF'},
    );
    final unmappedJson = unmappedResult.json!;
    expect(unmappedJson['type'], equals('FfiStructLayout'));
    final unmappedField0 = unmappedJson['fields'][0];
    expect(unmappedField0['readErrorType'], equals('SafeReadError'));
    expect(unmappedField0['readErrorReason'], equals('unmapped'));
    expect(unmappedField0['readErrorAddress'], equals('0xDEADBEEF'));

    // Test 4: layout without address — no readError fields, no value
    final layoutResult = await service.callServiceExtension(
      'getFfiStructLayout',
      isolateId: isolate.id,
      args: {'classId': edgeClassId},
    );
    final layoutJson = layoutResult.json!;
    expect(layoutJson['fields'][0].containsKey('readErrorType'), isFalse);
    expect(layoutJson['fields'][0].containsKey('value'), isFalse);
    expect(layoutJson['fields'][0]['byteOffset'], equals(0));
    expect(layoutJson['fields'][1]['byteOffset'], equals(4));

    // Test 5: read from large allocation bigger than one page — no crash
    final largeResult = await service.callServiceExtension(
      'getFfiStructLayout',
      isolateId: isolate.id,
      args: {'classId': edgeClassId, 'address': largeAddress},
    );
    final largeJson = largeResult.json!;
    expect(largeJson['type'], equals('FfiStructLayout'));
    expect(largeJson['fields'][0]['value'], equals(42));
    expect(largeJson['fields'][1]['value'], equals(99));

    // Test 6: misaligned address — offset by 1 byte, must not crash
    final misalignedAddress = (int.parse(edgeAddress) + 1).toString();
    final misalignedResult = await service.callServiceExtension(
      'getFfiStructLayout',
      isolateId: isolate.id,
      args: {'classId': edgeClassId, 'address': misalignedAddress},
    );
    final misalignedJson = misalignedResult.json!;
    expect(misalignedJson['type'], equals('FfiStructLayout'));
  },
];

void main([args = const <String>[]]) => runIsolateTests(
  args,
  tests,
  'ffi_memory_edge_cases_test.dart',
  testeeConcurrent: script,
);