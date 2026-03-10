// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:ffi';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';
import 'common/test_helper.dart';

// A simple FFI struct to test layout inspection
final class Point extends Struct {
  @Int32()
  external int x;

  @Int32()
  external int y;
}

// A struct with mixed types to test ABI-aware offsets
final class Mixed extends Struct {
  @Uint8()
  external int flag;

  @Int64()
  external int value;

  @Double()
  external double amount;
}

void script() {
  // Just instantiate so the classes are live
  final p = Pointer<Point>.fromAddress(0);
  final m = Pointer<Mixed>.fromAddress(0);
  print(p);
  print(m);
}

final tests = <IsolateTest>[
  (VmService service, IsolateRef isolateRef) async {
    final isolate = await service.getIsolate(isolateRef.id!);

    // Find the Point class ID
    final classes = await service.getClassList(isolate.id!);
    String? pointClassId;
    String? mixedClassId;

    for (final cls in classes.classes!) {
      if (cls.name == 'Point') pointClassId = cls.id;
      if (cls.name == 'Mixed') mixedClassId = cls.id;
    }

    expect(pointClassId, isNotNull, reason: 'Point class not found');
    expect(mixedClassId, isNotNull, reason: 'Mixed class not found');

    // Test Point struct layout
    final pointResult = await service.callServiceExtension(
      'getFfiStructLayout',
      isolateId: isolate.id,
      args: {'classId': pointClassId!},
    );

    final pointJson = pointResult.json!;
    expect(pointJson['type'], equals('FfiStructLayout'));
    expect(pointJson['totalSize'], equals(8)); // two Int32 = 8 bytes

    final pointFields = pointJson['fields'] as List;
    expect(pointFields.length, equals(2));
    expect(pointFields[0]['name'], equals('x'));
    expect(pointFields[0]['type'], equals('Int32'));
    expect(pointFields[0]['byteOffset'], equals(0));
    expect(pointFields[0]['size'], equals(4));

    expect(pointFields[1]['name'], equals('y'));
    expect(pointFields[1]['type'], equals('Int32'));
    expect(pointFields[1]['byteOffset'], equals(4));
    expect(pointFields[1]['size'], equals(4));

    // Test Mixed struct layout - verifies ABI padding is correct
    final mixedResult = await service.callServiceExtension(
      'getFfiStructLayout',
      isolateId: isolate.id,
      args: {'classId': mixedClassId!},
    );

    final mixedJson = mixedResult.json!;
    expect(mixedJson['type'], equals('FfiStructLayout'));

    final mixedFields = mixedJson['fields'] as List;
    expect(mixedFields.length, equals(3));

    // flag is Uint8 at offset 0
    expect(mixedFields[0]['name'], equals('flag'));
    expect(mixedFields[0]['byteOffset'], equals(0));
    expect(mixedFields[0]['size'], equals(1));

    // value is Int64 - should be at offset 8 due to alignment padding
    expect(mixedFields[1]['name'], equals('value'));
    expect(mixedFields[1]['byteOffset'], equals(8));
    expect(mixedFields[1]['size'], equals(8));

    // amount is Double at offset 16
    expect(mixedFields[2]['name'], equals('amount'));
    expect(mixedFields[2]['byteOffset'], equals(16));
    expect(mixedFields[2]['size'], equals(8));

    // total size = 24 bytes
    expect(mixedJson['totalSize'], equals(24));
  },
];

void main([args = const <String>[]]) => runIsolateTests(
      args,
      tests,
      'get_ffi_struct_layout_rpc_test.dart',
      testeeConcurrent: script,
    );