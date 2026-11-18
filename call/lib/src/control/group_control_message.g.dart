// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group_control_message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GroupControlMessage _$GroupControlMessageFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('GroupControlMessage', json, ($checkedConvert) {
  $checkKeys(
    json,
    allowedKeys: const [
      'kind',
      'callId',
      'groupId',
      'commandId',
      'senderSessionId',
      'targetUserId',
      'targetSessionId',
      'revision',
      'hostEpoch',
      'expiresAtMs',
      'device',
      'action',
      'allowed',
      'status',
      'deviceState',
      'hostId',
      'allowSelfUnmute',
      'muteBlocksUnmute',
      'allowVideo',
      'muteAll',
      'cameraAllClosed',
      'connectedAtMs',
      'deadlineMs',
      'sessions',
    ],
  );
  final val = GroupControlMessage(
    kind: $checkedConvert(
      'kind',
      (v) => $enumDecode(_$GroupControlMessageKindEnumMap, v),
    ),
    callId: $checkedConvert('callId', (v) => v as String),
    groupId: $checkedConvert('groupId', (v) => v as String),
    commandId: $checkedConvert('commandId', (v) => v as String),
    senderSessionId: $checkedConvert('senderSessionId', (v) => v as String),
    targetUserId: $checkedConvert('targetUserId', (v) => v as String),
    targetSessionId: $checkedConvert('targetSessionId', (v) => v as String),
    version: $checkedConvert('revision', (v) => (v as num).toInt()),
    hostEpoch: $checkedConvert('hostEpoch', (v) => (v as num).toInt()),
    expiresAtMs: $checkedConvert('expiresAtMs', (v) => (v as num?)?.toInt()),
    device: $checkedConvert(
      'device',
      (v) => $enumDecodeNullable(_$GroupControlDeviceEnumMap, v),
    ),
    action: $checkedConvert(
      'action',
      (v) => $enumDecodeNullable(_$GroupControlActionEnumMap, v),
    ),
    allowed: $checkedConvert('allowed', (v) => v as bool?),
    status: $checkedConvert(
      'status',
      (v) => $enumDecodeNullable(_$GroupControlAckStatusEnumMap, v),
    ),
    deviceState: $checkedConvert(
      'deviceState',
      (v) => $enumDecodeNullable(_$GroupControlDeviceStateEnumMap, v),
    ),
    hostId: $checkedConvert('hostId', (v) => v as String?),
    allowSelfUnmute: $checkedConvert('allowSelfUnmute', (v) => v as bool?),
    muteBlocksUnmute: $checkedConvert('muteBlocksUnmute', (v) => v as bool?),
    allowVideo: $checkedConvert('allowVideo', (v) => v as bool?),
    muteAll: $checkedConvert('muteAll', (v) => v as bool?),
    cameraAllClosed: $checkedConvert('cameraAllClosed', (v) => v as bool?),
    connectedAtMs: $checkedConvert(
      'connectedAtMs',
      (v) => (v as num?)?.toInt(),
    ),
    deadlineMs: $checkedConvert('deadlineMs', (v) => (v as num?)?.toInt()),
    sessions: $checkedConvert(
      'sessions',
      (v) =>
          (v as Map<String, dynamic>?)?.map((k, e) => MapEntry(k, e as String)),
    ),
  );
  return val;
}, fieldKeyMap: const {'version': 'revision'});

Map<String, dynamic> _$GroupControlMessageToJson(
  GroupControlMessage instance,
) => <String, dynamic>{
  'kind': _$GroupControlMessageKindEnumMap[instance.kind]!,
  'callId': instance.callId,
  'groupId': instance.groupId,
  'commandId': instance.commandId,
  'senderSessionId': instance.senderSessionId,
  'targetUserId': instance.targetUserId,
  'targetSessionId': instance.targetSessionId,
  'revision': instance.version,
  'hostEpoch': instance.hostEpoch,
  'expiresAtMs': ?instance.expiresAtMs,
  'device': ?_$GroupControlDeviceEnumMap[instance.device],
  'action': ?_$GroupControlActionEnumMap[instance.action],
  'allowed': ?instance.allowed,
  'status': ?_$GroupControlAckStatusEnumMap[instance.status],
  'deviceState': ?_$GroupControlDeviceStateEnumMap[instance.deviceState],
  'hostId': ?instance.hostId,
  'allowSelfUnmute': ?instance.allowSelfUnmute,
  'muteBlocksUnmute': ?instance.muteBlocksUnmute,
  'allowVideo': ?instance.allowVideo,
  'muteAll': ?instance.muteAll,
  'cameraAllClosed': ?instance.cameraAllClosed,
  'connectedAtMs': ?instance.connectedAtMs,
  'deadlineMs': ?instance.deadlineMs,
  'sessions': ?instance.sessions,
};

const _$GroupControlMessageKindEnumMap = {
  GroupControlMessageKind.hello: 'hello',
  GroupControlMessageKind.sync: 'sync',
  GroupControlMessageKind.command: 'command',
  GroupControlMessageKind.ack: 'ack',
  GroupControlMessageKind.transfer: 'transfer',
  GroupControlMessageKind.transferAck: 'transferAck',
};

const _$GroupControlDeviceEnumMap = {
  GroupControlDevice.microphone: 'microphone',
  GroupControlDevice.camera: 'camera',
};

const _$GroupControlActionEnumMap = {
  GroupControlAction.close: 'close',
  GroupControlAction.requestOpen: 'requestOpen',
  GroupControlAction.setAllowed: 'setAllowed',
};

const _$GroupControlAckStatusEnumMap = {
  GroupControlAckStatus.applied: 'applied',
  GroupControlAckStatus.rejected: 'rejected',
  GroupControlAckStatus.failed: 'failed',
  GroupControlAckStatus.expired: 'expired',
};

const _$GroupControlDeviceStateEnumMap = {
  GroupControlDeviceState.on: 'on',
  GroupControlDeviceState.off: 'off',
  GroupControlDeviceState.unavailable: 'unavailable',
  GroupControlDeviceState.unknown: 'unknown',
};
