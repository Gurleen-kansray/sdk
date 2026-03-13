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

void script() {
  validPtr = calloc<EdgeStruct>();
  validPtr.ref.a = 111;
  validPtr.ref.b = 222;
  print('edge_struct_address=${validPtr.address}');
}

final tests = <IsolateTest>[
  (VmService service, IsolateRef isolateRef) async {
    final isolate = await service.getIsolate(isolateRef.id!);

    // Find EdgeStruct class ID
    final classes = await service.getClassList(isolate.id!);
    String? classId;
    for (final cls in classes.classes!) {
      if (cls.name == 'EdgeStruct') classId = cls.id;
    }
    expect(classId, isNotNull, reason: 'EdgeStruct class not found');

    // Get real address
    final addrResult = await service.evaluate(
      isolate.id!,
      isolate.rootLib!.id!,
      'validPtr.address',
    );
    expect(addrResult, isA<InstanceRef>());
    final address = (addrResult as InstanceRef).valueAsString!;

    // Test 1: valid address — correct values
    final validResult = await service.callServiceExtension(
      'getFfiStructLayout',
      isolateId: isolate.id,
      args: {'classId': classId!, 'address': address},
    );
    final validJson = validResult.json!;
    expect(validJson['fields'][0]['value'], equals(111));
    expect(validJson['fields'][1]['value'], equals(222));

    // Test 2: null address — readError is "null"
    final nullResult = await service.callServiceExtension(
      'getFfiStructLayout',
      isolateId: isolate.id,
      args: {'classId': classId, 'address': '0'},
    );
    expect(nullResult.json!['fields'][0]['readError'], equals('null'));
    expect(nullResult.json!['fields'][1]['readError'], equals('null'));

    // Test 3: unmapped address — readError is "unmapped", no crash
    final unmappedResult = await service.callServiceExtension(
      'getFfiStructLayout',
      isolateId: isolate.id,
      args: {'classId': classId, 'address': '0xDEADBEEF'},
    );
    final unmappedJson = unmappedResult.json!;
    // Must not crash — type still returned
    expect(unmappedJson['type'], equals('FfiStructLayout'));
    expect(unmappedJson['fields'][0]['readError'], equals('unmapped'));

    // Test 4: layout without address — no readError, no value
    final layoutResult = await service.callServiceExtension(
      'getFfiStructLayout',
      isolateId: isolate.id,
      args: {'classId': classId},
    );
    final layoutJson = layoutResult.json!;
    expect(layoutJson['fields'][0].containsKey('readError'), isFalse);
    expect(layoutJson['fields'][0].containsKey('value'), isFalse);
    expect(layoutJson['fields'][0]['byteOffset'], equals(0));
    expect(layoutJson['fields'][1]['byteOffset'], equals(4));
  },
];

void main([args = const <String>[]]) => runIsolateTests(
  args,
  tests,
  'ffi_memory_edge_cases_test.dart',
  testeeConcurrent: script,
);