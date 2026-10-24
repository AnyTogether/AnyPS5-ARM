import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anyps5_remote/together/friends.dart';
import 'package:anyps5_remote/together/messages.dart';
import 'package:anyps5_remote/together/parties.dart';
import 'package:anyps5_remote/together/people.dart';
import 'package:anyps5_remote/together/together_account.dart';
import 'package:anyps5_remote/together/together_socket.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The phone's AnyTogether client in the cross-client scenarios that the server's repository runs
/// (AnyTogether's e2e/): with ANYTOGETHER_E2E_BUS and ANYTOGETHER_E2E_URL set, this test takes
/// commands from the scenario script and runs each with the phone's real account, socket, friends,
/// messages and parties against the local stack, while the Mac, the Windows/Linux launcher and the
/// website do the same. Without them it is skipped.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final environment = Platform.environment;
  final bus = environment['ANYTOGETHER_E2E_BUS'];
  final base = environment['ANYTOGETHER_E2E_URL'];

  test(
    'drives the phone from the cross-client scenarios',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      await _Driver(
        Uri.parse(base!),
        preferences,
      ).run(Uri.parse(bus!), environment['ANYTOGETHER_E2E_ROLE'] ?? 'phone');
    },
    skip: bus == null || base == null ? 'no cross-client run' : false,
    timeout: Timeout.none,
  );
}

/// One phone: its account, socket and the lists the app shows, and what the socket said.
class _Phone {
  _Phone(this.account) : socket = TogetherSocket(account: account) {
    friends = Friends(account: account, socket: socket);
    messages = Messages(account: account, socket: socket);
    parties = Parties(account: account, socket: socket);
    socket.events.listen(events.add);
  }

  final TogetherAccount account;
  final TogetherSocket socket;
  late final Friends friends;
  late final Messages messages;
  late final Parties parties;
  final events = <TogetherEvent>[];
}

class _Driver {
  _Driver(this.base, this.preferences);

  final Uri base;
  final SharedPreferences preferences;
  final _phones = <String, _Phone>{};
  final _http = HttpClient();

  _Phone phone(String name) => _phones[name] ??= _Phone(
    TogetherAccount(
      // Each phone keeps its session apart: one preferences store would make them one phone.
      preferences: _NamedPreferences.of(preferences, name),
      base: base,
      clientName: 'phone-ios/e2e',
    ),
  );

  Future<void> run(Uri bus, String role) async {
    await _post(bus.resolve('/hello'), {'role': role});
    var done = false;
    while (!done) {
      final request = await _http.getUrl(bus.resolve('/next?role=$role'));
      final response = await request.close();
      final text = await utf8.decodeStream(response);
      if (response.statusCode != 200) continue;
      final command = jsonDecode(text) as Map<String, dynamic>;
      final id = command['id'] as String;
      final name = command['cmd'] as String;
      final args = (command['args'] as Map<String, dynamic>?) ?? const {};
      if (name == 'done') {
        done = true;
        await _post(bus.resolve('/result'), {'id': id, 'ok': true});
        continue;
      }
      unawaited(() async {
        Map<String, dynamic> answer;
        try {
          answer = {'id': id, 'ok': true, 'value': await handle(name, args)};
        } on TogetherProblem catch (problem) {
          answer = {
            'id': id,
            'ok': false,
            'error': {
              'status': problem.status,
              'code': problem.code,
              'message': problem.title,
            },
          };
        } on Object catch (error) {
          answer = {
            'id': id,
            'ok': false,
            'error': {'message': '$error'},
          };
        }
        await _post(bus.resolve('/result'), answer);
      }());
    }
    for (final phone in _phones.values) {
      phone.socket.stop();
    }
  }

  Future<void> _post(Uri url, Map<String, dynamic> body) async {
    final request = await _http.postUrl(url);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    await (await request.close()).drain<void>();
  }

  Future<Object?> handle(String name, Map<String, dynamic> args) async {
    final who = phone(args['as'] as String? ?? 'main');
    final account = who.account;
    String text(String key) => args[key] as String;
    switch (name) {
      // Signing in
      case 'emailStart':
        await account.startEmail(text('email'));
        return null;
      case 'emailVerify':
        return account.verifyEmail(text('code')).then(_user);
      case 'handoffStart':
        final handoff = await account.startHandoff(text('deviceName'));
        return {'handoffId': handoff.id, 'secret': handoff.secret};
      case 'handoffWait':
        return account
            .waitForApproval(
              Handoff(text('handoffId'), text('secret')),
              every: const Duration(milliseconds: 500),
              within: const Duration(minutes: 1),
            )
            .then(_user);
      case 'handoffApprove':
        await account.approveHandoff(text('id'));
        return null;
      case 'user':
        return account.user == null ? null : _user(account.user!);
      case 'signOut':
        who.socket.stop();
        await account.signOut();
        return null;

      // The socket
      case 'socketStart':
        who.socket.start();
        return null;
      case 'socketStatus':
        return {
          'status': who.socket.status.name,
          'session': who.socket.session,
        };
      case 'events':
        final since = (args['since'] as num? ?? 0).toInt();
        return {
          'next': who.events.length,
          'events': [
            for (final event in who.events.skip(since))
              {'type': event.type, 'data': event.data},
          ],
        };
      case 'frame':
        return who.socket.send(args['frame'] as Map<String, dynamic>);

      // Friends, as the friends list keeps them
      case 'friends':
        final friends = who.friends;
        return {
          'loaded': friends.loaded,
          'friends': [
            for (final friend in friends.friends)
              {
                ..._person(friend.person),
                'state': friend.presence.state.name,
                'titleId': friend.presence.titleId,
                'partyId': friend.presence.partyId,
              },
          ],
          'incoming': friends.incoming.map(_person).toList(),
          'outgoing': friends.outgoing.map(_person).toList(),
        };
      case 'friendsRefresh':
        await who.friends.refresh();
        return null;
      case 'addFriend':
        return who.friends.add(text('handle'));
      case 'answerFriend':
        await who.friends.answer(
          text('userId'),
          accept: args['accept'] == true,
        );
        return null;
      case 'removeFriend':
        await who.friends.remove(text('userId'));
        return null;

      // Messages, as the messages screen keeps them
      case 'messages':
        final messages = who.messages;
        return {
          'loaded': messages.loaded,
          'unread': messages.unread,
          'openId': messages.openId,
          'conversations': [
            for (final c in messages.conversations)
              {
                'id': c.id,
                'group': c.group,
                'title': c.title,
                'unread': c.unread,
                'lastSeq': c.lastSeq,
                'readSeq': c.readSeq,
                'last': c.lastMessage?.text,
                'members': c.members.map((p) => p.id).toList(),
              },
          ],
          'thread': [
            for (final m in messages.thread)
              {
                'seq': m.seq,
                'authorId': m.authorId,
                'text': m.text,
                'pending': m.pending,
                'failed': m.failed,
              },
          ],
        };
      case 'messagesRefresh':
        await who.messages.refresh();
        return null;
      case 'withFriend':
        await who.messages.withFriend(text('userId'));
        return who.messages.openId;
      case 'show':
        await who.messages.show(text('id'));
        return null;
      case 'hide':
        who.messages.hide();
        return null;
      case 'sendMessage':
        await who.messages.send(text('text'));
        return null;

      // Parties, as the party screen keeps them
      case 'parties':
        final party = who.parties.party;
        return {
          'loaded': who.parties.loaded,
          'kicked': who.parties.kicked,
          'party': party == null
              ? null
              : {
                  'id': party.id,
                  'leaderId': party.leaderId,
                  'open': party.open,
                  'members': party.members.map((p) => p.id).toList(),
                  'invited': party.invited.map((p) => p.id).toList(),
                  'callId': party.callId,
                  'inCall': party.inCall.toList(),
                },
          'invites': [
            for (final invite in who.parties.invites)
              {
                'partyId': invite.partyId,
                'from': invite.from?.id,
                'size': invite.size,
              },
          ],
        };
      case 'partiesRefresh':
        await who.parties.refresh();
        return null;
      case 'createParty':
        await who.parties.create(open: args['open'] == true);
        return who.parties.party?.id;
      case 'inviteParty':
        await who.parties.invite([
          for (final id in args['userIds'] as List) id as String,
        ]);
        return null;
      case 'joinParty':
        await who.parties.join(text('partyId'));
        return null;
      case 'declineParty':
        await who.parties.decline(text('partyId'));
        return null;
      case 'leaveParty':
        await who.parties.leave();
        return null;
      case 'kick':
        await who.parties.kick(text('userId'));
        return null;

      // Anything else the API has, with the phone's session
      case 'api':
        return account.call(
          text('method'),
          text('path'),
          args['body'] as Map<String, dynamic>?,
        );
      default:
        throw StateError('unknown command $name');
    }
  }

  static Map<String, dynamic> _user(TogetherUser user) => user.toJson();

  static Map<String, dynamic> _person(Person person) => {
    'userId': person.id,
    'handle': person.handle,
    'displayName': person.displayName,
  };
}

/// One phone's share of the test's preferences: its own keys, so each driven phone keeps its own
/// session as a real one would.
class _NamedPreferences implements SharedPreferences {
  _NamedPreferences(this._inner, this._name);

  static final _made = <String, _NamedPreferences>{};
  static _NamedPreferences of(SharedPreferences inner, String name) =>
      _made[name] ??= _NamedPreferences(inner, name);

  final SharedPreferences _inner;
  final String _name;
  String _key(String key) => '$_name/$key';

  @override
  String? getString(String key) => _inner.getString(_key(key));
  @override
  Future<bool> setString(String key, String value) =>
      _inner.setString(_key(key), value);
  @override
  Future<bool> remove(String key) => _inner.remove(_key(key));
  @override
  bool containsKey(String key) => _inner.containsKey(_key(key));
  @override
  Object? get(String key) => _inner.get(_key(key));
  @override
  bool? getBool(String key) => _inner.getBool(_key(key));
  @override
  Future<bool> setBool(String key, bool value) =>
      _inner.setBool(_key(key), value);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
