import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_calls_uikit/src/manager/call_peer_organization.dart';
import 'package:tencent_calls_uikit/src/manager/group_member_subtitle_cache.dart';
import 'package:tencent_calls_uikit/src/state/group_call_snapshot.dart';
import 'package:tuikit_atomic_x/atomicx.dart';

import 'support/call_fakes.dart';

void main() {
  test('单聊横幅和全屏共用对端资料，换场后忽略上一场回包', () async {
    final organization = CallPeerOrganization();
    addTearDown(organization.dispose);
    final pending = <Completer<Map<String, String>>>[];
    organization.setLoader((account, ids) {
      expect(account, 'self');
      expect(ids, ['peer']);
      final result = Completer<Map<String, String>>();
      pending.add(result);
      return result.future;
    });

    organization.refresh('self', 'first', 'peer');
    organization.refresh('self', 'first', 'peer');
    expect(pending, hasLength(1));
    organization.refresh('self', 'second', 'peer');
    expect(pending, hasLength(2));
    pending.first.complete({'peer': '旧组织'});
    pending.last.complete({'peer': '  新组织 I 研发  '});
    await Future<void>.delayed(Duration.zero);
    expect(organization.forPeer('first', 'peer'), isEmpty);
    expect(organization.forPeer('second', 'other'), isEmpty);
    expect(organization.forPeer('second', 'peer'), '新组织 I 研发');

    organization.clear();
    expect(organization.forPeer('second', 'peer'), isEmpty);
  });

  late GroupCallSession session;
  late GroupMemberSubtitleCache cache;
  late String account;

  void begin(String id) => session.begin(
      callId: id,
      groupId: 'group',
      groupName: '研发',
      inviterId: 'self',
      mediaType: CallMediaType.audio,
      memberIds: ['self', 'a']);

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    account = 'self';
    session = GroupCallSession();
    begin('');
    cache =
        GroupMemberSubtitleCache(session: session, accountId: () => account);
  });
  tearDown(() {
    cache.dispose();
    session.dispose();
  });

  test('按账号查询真实资料，SDK回填场次不重查，快照不可变且状态更新保留资料', () async {
    final pending = Completer<Map<String, String>>();
    var requests = 0;
    cache.setLoader((id, users) {
      requests++;
      expect(id, 'self');
      expect(users, ['self', 'a']);
      expect(() => users.add('unexpected'), throwsUnsupportedError);
      return pending.future;
    });
    session.sync(
        FakeCallInfo(callId: 'sdk-id', mediaType: CallMediaType.audio), []);
    expect(requests, 1);
    pending.complete({'a': '  研发部 · 工程师 ', 'self': ' ', 'stranger': '错误资料'});
    await settle();
    expect(session.value!.subtitleById, {'a': '研发部 · 工程师'});
    expect(
        () => session.value!.subtitleById['a'] = '改写', throwsUnsupportedError);
    session.updateMember('a', GroupCallMemberStatus.rejected);
    session.updateGroupTitle('group', '真实新群名');
    session.end('sdk-id', CallEndReason.noResponse, isCaller: true);
    expect(session.value!.subtitleById, {'a': '研发部 · 工程师'});
    expect(requests, 1);
  });

  test('成员集变化丢弃迟到结果，已成功查询的成员在同场不重复加载', () async {
    final pending = <Completer<Map<String, String>>>[];
    final requested = <List<String>>[];
    cache.setLoader((_, ids) {
      requested.add(ids);
      final result = Completer<Map<String, String>>();
      pending.add(result);
      return result.future;
    });
    session.updateMember('b', GroupCallMemberStatus.waiting);
    pending[0].complete({'a': '旧成员集资料'});
    await settle();
    expect(session.value!.subtitleById, isEmpty);
    pending[1].complete({'a': '研发', 'b': '运营'});
    await settle();
    session.updateMember('c', GroupCallMemberStatus.waiting);
    expect(requested, [
      ['self', 'a'],
      ['self', 'a', 'b'],
      ['c']
    ]);
    pending[2].complete({'c': '财务', 'a': '越界覆盖'});
    await settle();
    expect(session.value!.subtitleById, {'a': '研发', 'b': '运营', 'c': '财务'});
  });

  test('切号立即清理旧资料，新场及注销使待返回结果失效', () async {
    final pending = <Completer<Map<String, String>>>[];
    final accounts = <String>[];
    cache.setLoader((id, _) {
      accounts.add(id);
      final result = Completer<Map<String, String>>();
      pending.add(result);
      return result.future;
    });
    pending[0].complete({'a': '原账号资料'});
    await settle();
    account = 'next-account';
    cache.refresh();
    expect(session.value!.subtitleById, isEmpty);
    expect(accounts, ['self', 'next-account']);
    begin('next-call');
    pending[1].complete({'a': '旧场次迟到资料'});
    await settle();
    expect(session.value!.subtitleById, isEmpty);
    session.clear();
    pending[2].complete({'a': '注销后迟到资料'});
    await settle();
    expect(session.value, isNull);
  });

  test('失败不随高频通知重复请求，替换或注销loader丢弃旧结果', () async {
    var requests = 0;
    cache.setLoader((_, __) async {
      requests++;
      throw StateError('资料服务不可用');
    });
    await settle();
    for (var i = 0; i < 3; i++) {
      session.sync(
          FakeCallInfo(callId: 'sdk-id', mediaType: CallMediaType.audio), []);
    }
    expect(requests, 1);
    final previousLoader = Completer<Map<String, String>>();
    cache.setLoader((_, __) => previousLoader.future);
    cache.setLoader((_, __) async => {'a': '最新资料'});
    await settle();
    previousLoader.complete({'a': '旧查询器迟到资料'});
    await settle();
    expect(session.value!.subtitleById, {'a': '最新资料'});
    cache.setLoader(null);
    expect(session.value!.subtitleById, isEmpty);
  });
}
