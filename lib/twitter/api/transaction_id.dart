// Dart adaptation of fa0311/x-client-transaction-id-generater 0.0.7 (MIT).
// The complete upstream MIT notice is in licenses/fa0311-transaction-mit.txt.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

class TransactionIds {
  TransactionIds({Random? random, DateTime Function()? clock})
      : _random = random ?? Random.secure(),
        _clock = clock ?? DateTime.now;

  static const _pairAsset = 'assets/x_transaction_pairs.json';
  static const _unixEpochOffset = 1682924400;

  final Random _random;
  final DateTime Function() _clock;
  List<_TransactionPair>? _pairs;
  Future<List<_TransactionPair>>? _loading;

  Future<String> create(String method, String path) async {
    final pairs = _pairs ?? await (_loading ??= _loadPairs());
    final pair = pairs[_random.nextInt(pairs.length)];
    final now = _clock().millisecondsSinceEpoch ~/ 1000 - _unixEpochOffset;
    return encode(
      method: method,
      path: path,
      verification: pair.verification,
      animationKey: pair.animationKey,
      time: now,
      mask: _random.nextInt(256),
    );
  }

  Future<List<_TransactionPair>> _loadPairs() async {
    try {
      final source = await rootBundle.loadString(_pairAsset);
      final decoded = jsonDecode(source);
      if (decoded is! List) {
        throw const FormatException('Transaction pair asset must be a list');
      }
      final pairs = <_TransactionPair>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final verification = item['verification'];
        final animationKey = item['animationKey'];
        if (verification is! String || animationKey is! String) continue;
        if (verification.isEmpty || animationKey.isEmpty) continue;
        try {
          if (base64.decode(verification).isEmpty) continue;
        } on FormatException {
          continue;
        }
        pairs.add(_TransactionPair(verification, animationKey));
      }
      if (pairs.isEmpty) {
        throw const FormatException('No valid X transaction pairs');
      }
      return _pairs = pairs;
    } finally {
      _loading = null;
    }
  }

  static String encode({
    required String method,
    required String path,
    required String verification,
    required String animationKey,
    required int time,
    required int mask,
  }) {
    if (time < 0 || time > 0xffffffff) {
      throw RangeError.range(time, 0, 0xffffffff, 'time');
    }
    if (mask < 0 || mask > 0xff) {
      throw RangeError.range(mask, 0, 0xff, 'mask');
    }

    final timestamp = ByteData(4)..setUint32(0, time, Endian.little);
    final message =
        utf8.encode('$method!$path!${time}obfiowerehiring$animationKey');
    final digest = sha256.convert(message).bytes;
    final payload = <int>[
      ...base64.decode(verification),
      ...timestamp.buffer.asUint8List(),
      ...digest.take(16),
      3,
    ];

    final output = Uint8List(payload.length + 1);
    output[0] = mask;
    for (var i = 0; i < payload.length; i++) {
      output[i + 1] = payload[i] ^ mask;
    }
    return base64Encode(output).replaceAll('=', '');
  }
}

class _TransactionPair {
  const _TransactionPair(this.verification, this.animationKey);

  final String verification;
  final String animationKey;
}
