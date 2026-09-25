import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Small user-created presets, not the crash-safe session snapshot roadmap.
class PlayerPreset {
  const PlayerPreset({
    required this.id,
    required this.name,
    required this.title,
    required this.sourceId,
    required this.locator,
    required this.youtube,
    required this.pitch,
    required this.speed,
    required this.positionMs,
    this.aMs,
    this.bMs,
    this.loop = false,
  });
  final String id, name, title, sourceId, locator;
  final bool youtube, loop;
  final double pitch, speed;
  final int positionMs;
  final int? aMs, bMs;

  PlayerPreset renamed(String name) => PlayerPreset(
    id: id,
    name: name,
    title: title,
    sourceId: sourceId,
    locator: locator,
    youtube: youtube,
    pitch: pitch,
    speed: speed,
    positionMs: positionMs,
    aMs: aMs,
    bMs: bMs,
    loop: loop,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'title': title,
    'sourceId': sourceId,
    'locator': locator,
    'youtube': youtube,
    'pitch': pitch,
    'speed': speed,
    'positionMs': positionMs,
    'aMs': aMs,
    'bMs': bMs,
    'loop': loop,
  };

  static PlayerPreset? parse(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final m = value;
    if ([
      'id',
      'name',
      'title',
      'sourceId',
      'locator',
    ].any((k) => m[k] is! String || (m[k] as String).trim().isEmpty)) {
      return null;
    }
    final Object? pitch = m['pitch'], speed = m['speed'];
    final Object? pos = m['positionMs'], a = m['aMs'], b = m['bMs'];
    if (pitch is! num ||
        !pitch.isFinite ||
        pitch < -12 ||
        pitch > 12 ||
        speed is! num ||
        !speed.isFinite ||
        speed < 0.5 ||
        speed > 1.5 ||
        pos is! int ||
        pos < 0 ||
        m['youtube'] is! bool ||
        m['loop'] is! bool ||
        (a != null && (a is! int || a < 0)) ||
        (b != null && (b is! int || a is! int || b - a < 250))) {
      return null;
    }
    if (m['loop'] == true && (a == null || b == null)) return null;
    return PlayerPreset(
      id: m['id'],
      name: m['name'],
      title: m['title'],
      sourceId: m['sourceId'],
      locator: m['locator'],
      youtube: m['youtube'],
      pitch: pitch.toDouble(),
      speed: speed.toDouble(),
      positionMs: pos,
      aMs: a as int?,
      bMs: b as int?,
      loop: m['loop'],
    );
  }
}

class PlayerPresetStore {
  PlayerPresetStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _preferences;
  static const _key = 'transpono.player.collections.v1';
  // Separate views may each create a store. Serialize their read/modify/write
  // operations too; otherwise a rename can overwrite a simultaneous save.
  static Future<void>? _tail;

  Future<Map<String, dynamic>> _read() async {
    final String? raw = await _preferences.getString(_key);
    if (raw == null) return <String, dynamic>{};
    try {
      final Object? value = jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          (value['presets'] != null && value['presets'] is! List) ||
          (value['setlist'] != null && value['setlist'] is! List)) {
        throw const FormatException('Formato de coleção inválido.');
      }
      return value;
    } on FormatException {
      throw const FormatException(
        'As predefinições guardadas não puderam ser lidas.',
      );
    }
  }

  Future<List<PlayerPreset>> list({bool setlist = false}) async {
    final pending = _tail;
    if (pending != null) await pending;
    final data = await _read();
    final Object? values = data[setlist ? 'setlist' : 'presets'];
    if (values is! List) return <PlayerPreset>[];
    return values.map(PlayerPreset.parse).whereType<PlayerPreset>().toList();
  }

  Future<void> _edit(
    bool setlist,
    void Function(List<Object?> entries) update,
  ) {
    final result = (_tail ?? Future<void>.value()).then((_) async {
      final data = await _read();
      final key = setlist ? 'setlist' : 'presets';
      final Object? raw = data[key];
      // Preserve unreadable older entries for recovery; listing merely skips
      // them. Saving a new preset must not silently erase unrelated records.
      final entries = raw is List ? List<Object?>.of(raw) : <Object?>[];
      update(entries);
      data[key] = entries;
      await _preferences.setString(_key, jsonEncode(data));
    });
    final settled = result.catchError((Object _) {});
    _tail = settled;
    settled.then((_) {
      if (identical(_tail, settled)) _tail = null;
    });
    return result;
  }

  Future<void> save(PlayerPreset preset, {bool setlist = false}) =>
      _edit(setlist, (entries) {
        if (PlayerPreset.parse(preset.toJson()) == null) {
          throw ArgumentError('Os ajustes a guardar são inválidos.');
        }
        if (entries.length >= 200) {
          throw StateError('Limite de 200 itens atingido.');
        }
        if (entries.any((entry) => entry is Map && entry['id'] == preset.id)) {
          throw StateError('Já existe um item com este identificador.');
        }
        entries.add(preset.toJson());
      });

  int _indexOf(List<Object?> entries, String id) {
    final indices = <int>[
      for (var i = 0; i < entries.length; i++)
        if (PlayerPreset.parse(entries[i])?.id == id) i,
    ];
    if (indices.length != 1) {
      throw StateError(
        indices.isEmpty
            ? 'O item já não está nesta coleção. Atualize a lista.'
            : 'Há identificadores duplicados. Os dados foram preservados.',
      );
    }
    return indices.single;
  }

  Future<void> rename(String id, String name, {bool setlist = false}) =>
      _edit(setlist, (entries) {
        final cleaned = name.trim();
        if (cleaned.isEmpty || cleaned.length > 120) {
          throw ArgumentError('Use um nome entre 1 e 120 caracteres.');
        }
        final index = _indexOf(entries, id);
        // Keep unknown fields from future versions, not just known metadata.
        entries[index] = <String, dynamic>{
          ...entries[index] as Map<String, dynamic>,
          'name': cleaned,
        };
      });

  Future<void> delete(String id, {bool setlist = false}) =>
      _edit(setlist, (entries) => entries.removeAt(_indexOf(entries, id)));

  /// Reorders every visible item. Invalid legacy entries remain in their
  /// original slots and are never discarded by a display-only operation.
  Future<void> reorder(List<String> ids, {bool setlist = false}) => _edit(
    setlist,
    (entries) {
      final visible = <String, Object?>{};
      var count = 0;
      for (final entry in entries) {
        final parsed = PlayerPreset.parse(entry);
        if (parsed != null) {
          count++;
          visible[parsed.id] = entry;
        }
      }
      if (count != visible.length ||
          ids.length != count ||
          ids.toSet().length != count ||
          ids.any((id) => !visible.containsKey(id))) {
        throw StateError('A coleção mudou. Atualize a lista e tente de novo.');
      }
      var next = 0;
      for (var i = 0; i < entries.length; i++) {
        if (PlayerPreset.parse(entries[i]) != null) {
          entries[i] = visible[ids[next++]];
        }
      }
    },
  );
}
