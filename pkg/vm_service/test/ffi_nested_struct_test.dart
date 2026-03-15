// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';
import 'common/test_helper.dart';

final class Inner extends Struct {
  @Int32()
  external int value;

  @Double()
  external double ratio;
}

final class Outer extends Struct {
  @Int32()
  external int id;

  external Inner inner;

  @Int32()
  external int count;
}

late Pointer<Outer> outerPtr;

void script() {
  outerPtr = calloc<Outer>();
  outerPtr.ref.id = 55;
  outerPtr.ref.inner.value = 777;
  outerPtr.ref.inner.ratio = 1.5;
  outerPtr.ref.count = 99;
  print('outer_struct_address=${outerPtr.address}');
}

final tests = <IsolateTest>[
  (VmService service, IsolateRef isolateRef) async {
    final isolate = await service.getIsolate(isolateRef.id!);

    final classes = await service.getClassList(isolate.id!);
    String? outerClassId;
    String? innerClassId;
    for (final cls in classes.classes!) {
      if (cls.name == 'Outer') outerClassId = cls.id;
      if (cls.name == 'Inner') innerClassId = cls.id;
    }
    expect(outerClassId, isNotNull, reason: 'Outer class not found');
    expect(innerClassId, isNotNull, reason: 'Inner class not found');

    final addrResult = await service.evaluate(
      isolate.id!,
      isolate.rootLib!.id!,
      'outerPtr.address',
    );
    expect(addrResult, isA<InstanceRef>());
    final address = (addrResult as InstanceRef).valueAsString!;

    // Test 1: Outer struct layout — field names and offsets
    final outerLayout = await service.callServiceExtension(
      'getFfiStructLayout',
      isolateId: isolate.id,
      args: {'classId': outerClassId!},
    );
    final outerJson = outerLayout.json!;
    expect(outerJson['type'], equals('FfiStructLayout'));
    expect(outerJson['fields'][0]['name'], equals('id'));
    expect(outerJson['fields'][0]['byteOffset'], equals(0));
    expect(outerJson['fields'][1]['name'], equals('inner'));
    expect(outerJson['fields'][2]['name'], equals('count'));

    // Test 2: Inner struct layout
    final innerLayout = await service.callServiceExtension(
      'getFfiStructLayout',
      isolateId: isolate.id,
      args: {'classId': innerClassId!},
    );
    final innerJson = innerLayout.json!;
    expect(innerJson['type'], equals('FfiStructLayout'));
    expect(innerJson['fields'][0]['name'], equals('value'));
    expect(innerJson['fields'][1]['name'], equals('ratio'));
    expect(innerJson['totalSize'], equals(16));

    // Test 3: Read Outer primitive fields with live address
    final outerLive = await service.callServiceExtension(
      'getFfiStructLayout',
      isolateId: isolate.id,
      args: {'classId': outerClassId, 'address': address},
    );
    final outerLiveJson = outerLive.json!;
    expect(outerLiveJson['fields'][0]['value'], equals(55));
    expect(outerLiveJson['fields'][2]['value'], equals(99));

    // Test 4: Read Inner struct fields using computed nested address
    // inner field offset from outer layout
    final innerOffset = outerJson['fields'][1]['byteOffset'] as int;
    final innerAddress = (int.parse(address) + innerOffset).toString();

    final innerLive = await service.callServiceExtension(
      'getFfiStructLayout',
      isolateId: isolate.id,
      args: {'classId': innerClassId, 'address': innerAddress},
    );
    final innerLiveJson = innerLive.json!;
    expect(innerLiveJson['fields'][0]['value'], equals(777));
    final innerRatio = double.parse(
        innerLiveJson['fields'][1]['value'] as String);
    expect(innerRatio, closeTo(1.5, 0.001));
  },
];

void main([args = const <String>[]]) => runIsolateTests(
  args,
  tests,
  'ffi_nested_struct_test.dart',
  testeeConcurrent: script,
);