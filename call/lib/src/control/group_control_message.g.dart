// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group_control_message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GroupControlMessage _$GroupControlMessageFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'GroupControlMessage',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          allowedKeys: const [
            'protocol',
            'schemaVersion',
            'kind',
            'callId',
            'commandId',
            'senderSessionId',
            'targetUserId',
            'targetSessionId',
            'version',
            'expiresAtMs',
            'hostId',
            'hostEpoch',
            'allowSelfUnmute',
            'allowVideo',
            'muteAll',
            'cameraAllClosed',
            'connectedAtMs',
            'deadlineMs',
            'sessions',
            'device',
            'enabled',
            'status',
            'microphoneOn',
            'cameraOn',
            'error'
          ],
        );
        final val = GroupControlMessage(
          protocol: $checkedConvert(
              'protocol', (v) => v as String? ?? 'zd.group-call.control.v1'),
          schemaVersion: $checkedConvert(
              'schemaVersion', (v) => (v as num?)?.toInt() ?? 1),
          kind: $checkedConvert(
              'kind', (v) => $enumDecode(_$GroupControlMessageKindEnumMap, v)),
          callId: $checkedConvert('callId', (v) => v as String),
          commandId: $checkedConvert('commandId', (v) => v as String),
          senderSessionId:
              $checkedConvert('senderSessionId', (v) => v as String),
          targetUserId: $checkedConvert('targetUserId', (v) => v as String),
          targetSessionId:
              $checkedConvert('targetSessionId', (v) => v as String),
          version: $checkedConvert('version', (v) => (v as num).toInt()),
          expiresAtMs:
              $checkedConvert('expiresAtMs', (v) => (v as num).toInt()),
          hostId: $checkedConvert('hostId', (v) => v as String? ?? ''),
          hostEpoch:
              $checkedConvert('hostEpoch', (v) => (v as num?)?.toInt() ?? 0),
          allowSelfUnmute:
              $checkedConvert('allowSelfUnmute', (v) => v as bool? ?? true),
          allowVideo: $checkedConvert('allowVideo', (v) => v as bool? ?? true),
          muteAll: $checkedConvert('muteAll', (v) => v as bool? ?? false),
          cameraAllClosed:
              $checkedConvert('cameraAllClosed', (v) => v as bool? ?? false),
          connectedAtMs:
              $checkedConvert('connectedAtMs', (v) => (v as num?)?.toInt()),
          deadlineMs:
              $checkedConvert('deadlineMs', (v) => (v as num?)?.toInt()),
          sessions: $checkedConvert(
              'sessions',
              (v) =>
                  (v as Map<String, dynamic>?)?.map(
                    (k, e) => MapEntry(k, e as String),
                  ) ??
                  const {}),
          device: $checkedConvert('device', (v) => v as String?),
          enabled: $checkedConvert('enabled', (v) => v as bool?),
          status: $checkedConvert('status', (v) => v as String?),
          microphoneOn: $checkedConvert('microphoneOn', (v) => v as bool?),
          cameraOn: $checkedConvert('cameraOn', (v) => v as bool?),
          error: $checkedConvert('error', (v) => v as String?),
        );
        return val;
      },
    );

Map<String, dynamic> _$GroupControlMessageToJson(
        GroupControlMessage instance) =>
    <String, dynamic>{
      'protocol': instance.protocol,
      'schemaVersion': instance.schemaVersion,
      'kind': _$GroupControlMessageKindEnumMap[instance.kind]!,
      'callId': instance.callId,
      'commandId': instance.commandId,
      'senderSessionId': instance.senderSessionId,
      'targetUserId': instance.targetUserId,
      'targetSessionId': instance.targetSessionId,
      'version': instance.version,
      'expiresAtMs': instance.expiresAtMs,
      'hostId': instance.hostId,
      'hostEpoch': instance.hostEpoch,
      'allowSelfUnmute': instance.allowSelfUnmute,
      'allowVideo': instance.allowVideo,
      'muteAll': instance.muteAll,
      'cameraAllClosed': instance.cameraAllClosed,
      'connectedAtMs': instance.connectedAtMs,
      'deadlineMs': instance.deadlineMs,
      'sessions': instance.sessions,
      'device': instance.device,
      'enabled': instance.enabled,
      'status': instance.status,
      'microphoneOn': instance.microphoneOn,
      'cameraOn': instance.cameraOn,
      'error': instance.error,
    };

const _$GroupControlMessageKindEnumMap = {
  GroupControlMessageKind.hello: 'hello',
  GroupControlMessageKind.sync: 'sync',
  GroupControlMessageKind.command: 'command',
  GroupControlMessageKind.policy: 'policy',
  GroupControlMessageKind.ack: 'ack',
  GroupControlMessageKind.transfer: 'transfer',
};
