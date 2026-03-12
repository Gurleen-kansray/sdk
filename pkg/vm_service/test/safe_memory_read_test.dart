// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';
import 'common/test_helper.dart';

final class TestStruct extends Struct {
  @Int32()
  external int x;

  @Int32()
  external int y;
}

late Pointer<TestStruct> structPtr;

void script() {
  structPtr = calloc<TestStruct>();
  structPtr.ref.x = 42;
  structPtr.ref.y = 99;
  print('struct_address=${structPtr.address}');
}

final tests = <IsolateTest>[
  (VmService service, IsolateRef isolateRef) async {
    final isolate = await service.getIsolate(isolateRef.id!);

    final classes = await service.getClassList(isolate.id!);
    String? classId;
    for (final cls in classes.classes!) {
      if (cls.name == 'TestStruct') classId = cls.id;
    }
    expect(classId, isNotNull, reason: 'TestStruct class not found');

    final addrResult = await service.evaluate(
      isolate.id!,
      isolate.rootLib!.id!,
      'structPtr.address',
    );
    expect(addrResult, isA<InstanceRef>());
    final address = (addrResult as InstanceRef).valueAsString!;

    // Test 1: layout only
    final layoutResult = await service.callServiceExtension(
      'getFfiStructLayout',
      isolateId: isolate.id,
      args: {'classId': classId!},
    );
    final layoutJson = layoutResult.json!;
    expect(layoutJson['type'], equals('FfiStructLayout'));
    expect(layoutJson['totalSize'], equals(8));
    expect(layoutJson['fields'][0]['name'], equals('x'));
    expect(layoutJson['fields'][0]['byteOffset'], equals(0));
    expect(layoutJson['fields'][0]['size'], equals(4));
    expect(layoutJson['fields'][1]['name'], equals('y'));
    expect(layoutJson['fields'][1]['byteOffset'], equals(4));
    expect(layoutJson['fields'][1]['size'], equals(4));

    // Test 2: live value reading via SafeMemoryRead()
    final liveResult = await service.callServiceExtension(
      'getFfiStructLayout',
      isolateId: isolate.id,
      args: {
        'classId': classId,
        'address': address,
      },
    );
    final liveJson = liveResult.json!;
    expect(liveJson['type'], equals('FfiStructLayout'));
    expect(liveJson['fields'][0]['name'], equals('x'));
    expect(liveJson['fields'][0]['value'], equals(42));
    expect(liveJson['fields'][1]['name'], equals('y'));
    expect(liveJson['fields'][1]['value'], equals(99));

    // Test 3: null address — no crash, safe behavior
    final nullResult = await service.callServiceExtension(
      'getFfiStructLayout',
      isolateId: isolate.id,
      args: {
        'classId': classId,
        'address': '0',
      },
    );
    final nullJson = nullResult.json!;
    expect(nullJson['type'], equals('FfiStructLayout'));
    expect(nullJson['fields'][0]['name'], equals('x'));
    expect(nullJson['fields'][1]['name'], equals('y'));
    expect(nullJson['fields'][0].containsKey('value'), isFalse);
  },
];

void main([args = const <String>[]]) => runIsolateTests(
  args,
  tests,
  'safe_memory_read_test.dart',
  testeeConcurrent: script,
);