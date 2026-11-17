// ignore_for_file: file_names

import 'dart:async';

import 'package:logger/web.dart';
import 'package:squadron/squadron.dart';
import 'package:test/test.dart';

import 'src/test_context.dart';
import 'worker_services/test_service.dart';
import 'worker_services/test_service_worker.dart';

Future<void> main() => TestContext.run(execute);

const testScript = '13_channel_factory_test.dart';

void execute(TestContext? tc) {
  if (tc == null) return;

  tc.launch(() {
    tc.group('- CHANNEL FACTORY', () {
      tc.test('- Wraps the platform channel', () async {
        var calls = 0;
        List? seenStartArgs;
        final worker = TestWorker(tc);
        worker.channelFactory =
            (exceptionManager, logger, entryPoint, startArgs) {
          calls++;
          seenStartArgs = startArgs;
          // A factory may simply decorate Squadron's own channel.
          return Channel.open(
              exceptionManager, logger, entryPoint, startArgs, null);
        };
        try {
          expect(await worker.ping(), isTrue);
          expect(await worker.finite(3).toList(), [0, 1, 2]);
          expect(calls, 1);
          expect(seenStartArgs, [TestService.startupOk]);
          expect(worker.isConnected, isTrue);
        } finally {
          worker.stop();
        }
      });

      tc.test('- Replaces the platform channel', () async {
        final opened = <_EchoChannel>[];
        final worker = TestWorker(tc);
        worker.channelFactory =
            (exceptionManager, logger, entryPoint, startArgs) async {
          final channel = _EchoChannel(exceptionManager, logger);
          opened.add(channel);
          return channel;
        };
        try {
          // No platform thread: the echo channel answers with the command id.
          expect(await worker.send(TestService.pingCommand),
              TestService.pingCommand);
          expect(
              await worker
                  .stream(TestService.finiteCommand, args: [1, 2, 3]).toList(),
              [1, 2, 3]);
          expect(opened, hasLength(1));
        } finally {
          worker.stop();
        }
        await opened.single.closed;
      });

      tc.test('- Opens once for concurrent first requests', () async {
        var calls = 0;
        final worker = TestWorker(tc);
        worker.channelFactory = (em, logger, entryPoint, startArgs) async {
          calls++;
          return _EchoChannel(em, logger);
        };
        try {
          await Future.wait([worker.send(1), worker.send(2), worker.send(3)]);
          expect(calls, 1);
        } finally {
          worker.stop();
        }
      });

      tc.test('- Factory errors fail the request', () async {
        final worker = TestWorker(tc);
        worker.channelFactory = (em, logger, entryPoint, startArgs) =>
            Future.error(StateError('no channel'));
        try {
          // Same as a failing Channel.open: the error reaches the caller.
          await expectLater(worker.ping(), throwsA(isA<StateError>()));
        } finally {
          worker.stop();
        }
      });

      tc.test('- No factory: Squadron\'s own channel', () async {
        final worker = TestWorker(tc);
        try {
          expect(worker.channelFactory, isNull);
          expect(await worker.ping(), isTrue);
        } finally {
          worker.stop();
        }
      });
    });
  });
}

/// A channel with no platform worker behind it: requests answer with their
/// command id, streaming requests echo their arguments.
class _EchoChannel implements Channel {
  _EchoChannel(this.exceptionManager, this.logger);

  @override
  final ExceptionManager exceptionManager;

  @override
  final Logger? logger;

  final _closed = Completer<void>();

  @override
  Future<void> get closed => _closed.future;

  @override
  Future<void> close() {
    if (!_closed.isCompleted) _closed.complete();
    return _closed.future;
  }

  @override
  PlatformChannel serialize() => throw UnsupportedError('not serializable');

  @override
  Channel share() => this;

  @override
  void cancelStream(StreamId streamId) {}

  @override
  void cancelToken(SquadronCancelationToken? token) {}

  @override
  Future<dynamic> sendRequest(int command, List args,
          {SquadronCancelationToken? token,
          bool inspectRequest = false,
          bool inspectResponse = false}) async =>
      command;

  @override
  Stream<dynamic> sendStreamingRequest(int command, List args,
          {SquadronCancelationToken? token,
          bool inspectRequest = false,
          bool inspectResponse = false}) =>
      Stream.fromIterable(args);
}
