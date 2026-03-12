// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';
import 'common/test_helper.dart';

// A simple struct to test memory reading
final class TestStruct extends Struct {
  @Int32()
  external int x;

  @Int32()
  external int y;
}

late Pointer<TestStruct> validPtr;

void script() {
  // Allocate a real struct with known values
  validPtr = calloc<TestStruct>();
  validPtr.ref.x = 42;
  validPtr.ref.y = 99;
  print('allocated struct at ${validPtr.address}');
  print('x=${validPtr.ref.x} y=${validPtr.ref.y}');
}

final tests = <IsolateTest>[
  (VmService service, IsolateRef isolateRef) async {
    final isolate = await service.getIsolate(isolateRef.id!);

    // Find TestStruct class ID
    final classes = await service.getClassList(isolate.id!);
    String? classId;
    for (final cls in classes.classes!) {
      if (cls.name == 'TestStruct') classId = cls.id;
    }
    expect(classId, isNotNull, reason: 'TestStruct class not found');

    // getFfiStructLayout should still work correctly
    final result = await service.callServiceExtension(
      'getFfiStructLayout',
      isolateId: isolate.id,
      args: {'classId': classId!},
    );

    final json = result.json!;
    expect(json['type'], equals('FfiStructLayout'));
    expect(json['totalSize'], equals(8)); // two Int32 = 8 bytes
    expect(json['fields'][0]['name'], equals('x'));
    expect(json['fields'][0]['byteOffset'], equals(0));
    expect(json['fields'][0]['size'], equals(4));
    expect(json['fields'][1]['name'], equals('y'));
    expect(json['fields'][1]['byteOffset'], equals(4));
    expect(json['fields'][1]['size'], equals(4));
  },
];

void main([args = const <String>[]]) => runIsolateTests(
  args,
  tests,
  'safe_memory_read_test.dart',
  testeeConcurrent: script,
);