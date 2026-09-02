/// Module:   GenerateTestUserSig
///
/// Description: generates UserSig for testing. UserSig is a security signature designed by Tencent Cloud for its cloud services.
///           It is calculated based on `SDKAppID`, `UserID`, and `EXPIRETIME` using the HMAC-SHA256 encryption algorithm.
///
/// Attention: do not use the code below in your commercial app. This is because:
///
///            The code may be able to calculate UserSig correctly, but it is only for quick testing of the SDK’s basic features, not for commercial apps.
///            `SECRETKEY` in client code can be easily decompiled and reversed, especially on web.
///             Once your key is disclosed, attackers will be able to steal your Tencent Cloud traffic.
///
///            The correct method is to deploy the `UserSig` calculation code and encryption key on your project server so that your app can request from your server a `UserSig` that is calculated whenever one is needed.
///           Given that it is more difficult to hack a server than a client app, server-end calculation can better protect your key.
///
/// Reference: https://cloud.tencent.com/document/product/647/17275#Server
///
/// 模块：GenerateTestUserSig
///
/// 描述：生成测试用的 UserSig。UserSig 是腾讯云为其云服务设计的安全签名。它是基于 `SDKAppID`、`UserID` 和 `EXPIRETIME` 并使用 HMAC-SHA256
/// 加密算法计算得出的。
///
/// 注意：请不要在你的商业应用中使用下面的代码。原因如下：
///
/// 这段代码可能可以正确计算 UserSig，但它只是用来快速测试 SDK 的基础功能，并不适用于商业应用。在客户端代码中的 `SECRETKEY` 很容易被反编译和逆向，尤其是在 web
/// 上。一旦你的密钥泄露，攻击者就可以窃取你的腾讯云流量。
///
/// 正确的方法是在你的项目服务器上部署 `UserSig` 计算代码和加密密钥，这样你的应用就可以向服务器请求按需计算的
/// `UserSig`。因为破解服务器比破解客户端应用难，所以服务器端计算可以更好地保护你的密钥。
///
/// 参考：https://cloud.tencent.com/document/product/647/17275#Server

// ignore_for_file: slash_for_doc_comments

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class GenerateTestUserSig {
  /**
   * Signature validity period, which should not be set too short
   * <p>
   * Unit: second
   * Default value: 604800 (7 days)
   *
   * 签名有效期，不要设置得太短
   *
   * 单位：秒 默认值：604800（7天）
   */
  static int expireTime = 604800;

  static genTestSig(String userId, int sdkAppId, String secretKey) {
    int currTime = _getCurrentTime();
    String sig = '';
    Map<String, dynamic> sigDoc = <String, dynamic>{};
    sigDoc.addAll({
      "TLS.ver": "2.0",
      "TLS.identifier": userId,
      "TLS.sdkappid": sdkAppId,
      "TLS.expire": expireTime,
      "TLS.time": currTime,
    });

    sig = _hmacsha256(
      identifier: userId,
      currTime: currTime,
      expire: expireTime,
      sdkAppId: sdkAppId,
      secretKey: secretKey,
    );
    sigDoc['TLS.sig'] = sig;
    String jsonStr = json.encode(sigDoc);
    List<int> compress = zlib.encode(utf8.encode(jsonStr));
    return _escape(content: base64.encode(compress));
  }

  static int _getCurrentTime() {
    return (DateTime.now().millisecondsSinceEpoch / 1000).floor();
  }

  static String _hmacsha256({
    required String identifier,
    required int currTime,
    required int expire,
    required int sdkAppId,
    required String secretKey,
  }) {
    int sdkappid = sdkAppId;
    String contentToBeSigned =
        "TLS.identifier:$identifier\nTLS.sdkappid:$sdkappid\nTLS.time:$currTime\nTLS.expire:$expire\n";
    Hmac hmacSha256 = Hmac(sha256, utf8.encode(secretKey));
    Digest hmacSha256Digest = hmacSha256.convert(
      utf8.encode(contentToBeSigned),
    );
    return base64.encode(hmacSha256Digest.bytes);
  }

  static String _escape({required String content}) {
    return content
        .replaceAll('\+', '*')
        .replaceAll('\/', '-')
        .replaceAll('=', '_');
  }
}
