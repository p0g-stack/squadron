// Verifies the loader script of a Web Assembly worker (see
// lib/src/_impl/web/_entry_point_uri.dart): the worker runs from a blob URL, so
// it cannot derive its own location, and the loader has to publish the URL of
// the worker's .wasm file before it imports the Dart runtime.
@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:squadron/src/_impl/web/_entry_point_uri.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

Future<String> _loaderScript(String entryPoint) async {
  final uri = EntryPointUri.from(Uri.parse(entryPoint), addRandomHash: false);
  addTearDown(uri.release);
  expect(uri.uri, startsWith('blob:'));
  final response = await web.window.fetch(uri.uri.toJS).toDart;
  return (await response.text().toDart).toDart;
}

void main() {
  test('wasm worker loader exposes the worker script url', () async {
    final script = await _loaderScript('/workers/js/test_worker.dart.wasm');

    final urlIndex = script.indexOf('const workerUri=');
    final exposeIndex = script.indexOf('globalThis.squadronWorkerScriptUrl=');
    final runtimeIndex = script.indexOf('let newRt=');

    expect(urlIndex, isNonNegative);
    expect(exposeIndex, greaterThan(urlIndex));
    expect(exposeIndex, lessThan(runtimeIndex));
    expect(script, contains('globalThis.squadronWorkerScriptUrl=workerUri;'));
  });

  test('javascript worker entry points keep their own url', () async {
    final uri = EntryPointUri.from(
        Uri.parse('https://example.com/worker.js'),
        addRandomHash: false);
    expect(uri.uri, 'https://example.com/worker.js');
    uri.release();
  });
}
