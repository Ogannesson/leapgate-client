import 'dart:convert';

import 'package:flutter_hbb/leapgate/settings/settings_api.dart';
import 'package:flutter_test/flutter_test.dart';

BotLookup lookup(String rust) =>
    BotLookup.fromJson(jsonDecode(rust) as Map<String, dynamic>);

void main() {
  test('BotLookup reads the JSON leapgate_bot_lookup returns', () {
    final ok = lookup(
        '{"result":"ok","chat":{"id":"-1001234567890","type":"supergroup","label":"Example group"}}');
    expect(ok.result, 'ok');
    expect(ok.chatId, '-1001234567890');
    expect(ok.chatType, 'supergroup');
    expect(ok.chatLabel, 'Example group');

    final noChat = lookup('{"result":"no_chat","text":""}');
    expect(noChat.result, 'no_chat');
    expect(noChat.chatId, '');

    final other = lookup(
        '{"result":"other","text":"Telegram API error: Conflict (error_code: 409)"}');
    expect(other.result, 'other');
    expect(other.text, 'Telegram API error: Conflict (error_code: 409)');
  });
}
