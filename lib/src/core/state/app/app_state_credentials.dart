part of '../app_state.dart';

/// Credential persistence belongs here; routing and playback keep using the
/// in-memory session owned by AppState.
extension _AppStateCredentials on AppState {
  static const _sessionScopePrefsKey = 'active_session_scope';
  static const _sessionRestoreDisabledPrefsKey = 'session_restore_disabled';

  String _sessionSecretKey() {
    var username = user?.username ?? '';
    if (username.isEmpty) {
      try {
        final stored = jsonDecode(_prefs?.getString('user') ?? '{}');
        username = asMap(stored)['username']?.toString() ?? '';
      } catch (_) {
        // A corrupt cached user is validated separately during startup.
      }
    }
    return '${_serverProfileSecretKey(SavedServerProfile(
      serverUrl: serverUrl,
      localServerUrl: localServerUrl,
      activeUrl: activeUrl,
      username: username,
      password: '',
      label: '',
      fnId: fnId,
      mode: serverMode,
    ))}.session';
  }

  Future<void> _restoreSessionCredentials() async {
    if (_prefs?.getBool(_sessionRestoreDisabledPrefsKey) == true) {
      token = null;
      gatewayCookie = null;
      return;
    }
    final key = _prefs?.getString(_sessionScopePrefsKey) ?? _sessionSecretKey();
    Map<String, String>? record;
    try {
      record = await _credentials.read(key);
    } catch (_) {
      // 钥匙串暂时不可用时按「没有会话」处理即可：走登录页重新登录，但
      // 已保存的服务器列表不受影响，地址和用户名都还在偏好表里。
      record = null;
    }
    var legacySecretsMigrated = true;
    if (record == null) {
      final legacyToken = _prefs?.getString('auth_token');
      final legacyCookie = _prefs?.getString(AppState._gatewayCookiePrefsKey);
      if (legacyToken != null || legacyCookie != null) {
        record = {
          'token': legacyToken ?? '',
          'cookie': legacyCookie ?? '',
        };
        try {
          await _credentials.write(key, record);
          await _prefs?.setString(_sessionScopePrefsKey, key);
        } catch (_) {
          // 钥匙串写不进去时（换签名覆盖安装、设备尚未解锁）保留偏好表里的
          // 明文副本，下次启动再迁移一次。这里不能往外抛：启动流程一旦失败
          // 就会跳回登录页，而登录页空着列表正是用户以为账号丢了的原因。
          legacySecretsMigrated = false;
        }
      }
    }
    // Leave old values untouched if writing/verification throws.
    if (legacySecretsMigrated) {
      await _prefs?.remove('auth_token');
      await _prefs?.remove(AppState._gatewayCookiePrefsKey);
    }
    token = _nonEmptyCredential(record?['token']);
    gatewayCookie = _nonEmptyCredential(record?['cookie']);
  }

  Future<void> _persistSessionCredentials() async {
    final key = user == null
        ? (_prefs?.getString(_sessionScopePrefsKey) ?? _sessionSecretKey())
        : _sessionSecretKey();
    await _credentials.write(key, {
      'token': token ?? '',
      'cookie': gatewayCookie ?? '',
    });
    await _prefs?.setString(_sessionScopePrefsKey, key);
    await _prefs?.remove(_sessionRestoreDisabledPrefsKey);
    await _prefs?.remove('auth_token');
    await _prefs?.remove(AppState._gatewayCookiePrefsKey);
  }

  Future<void> _clearPersistedToken() async {
    final key = _prefs?.getString(_sessionScopePrefsKey) ?? _sessionSecretKey();
    final record = await _credentials.read(key);
    if (record != null) {
      await _credentials.write(key, {...record, 'token': ''});
    }
    await _prefs?.remove('auth_token');
  }

  Future<void> _clearPersistedSession() async {
    final key = _prefs?.getString(_sessionScopePrefsKey) ?? _sessionSecretKey();
    // Record logout before touching the keychain: a storage failure must not
    // restore the old session when the platform keychain becomes available.
    await _prefs?.setBool(_sessionRestoreDisabledPrefsKey, true);
    await _prefs?.remove('auth_token');
    await _prefs?.remove(AppState._gatewayCookiePrefsKey);
    await _prefs?.remove(AppState._gatewayReloginRequiredPrefsKey);
    await _prefs?.remove('user');
    await _credentials.delete(key);
    final profiles = <SavedServerProfile>[];
    for (final profile in savedServers) {
      if ('${_serverProfileSecretKey(profile)}.session' == key) {
        final cleared = profile.copyWith(gatewayCookie: '');
        await _storeServerProfileSecrets(cleared);
        profiles.add(cleared);
      } else {
        profiles.add(profile);
      }
    }
    savedServers = profiles;
    await _persistSavedServers(profiles);
    await _prefs?.remove(_sessionScopePrefsKey);
    await _prefs?.remove('auth_token');
    await _prefs?.remove(AppState._gatewayCookiePrefsKey);
  }

  String? _nonEmptyCredential(String? value) =>
      value == null || value.isEmpty ? null : value;

  /// 只解析偏好表里的服务器索引，不碰钥匙串。
  ///
  /// 地址和用户名本来就以明文存在偏好表里，密码在钥匙串。钥匙串读不出来时
  /// 也要能拿回这几条记录，否则用户会看到服务器「全部消失」。
  List<SavedServerProfile> _readSavedServersFromPrefs() {
    final raw = _prefs?.getString('saved_servers');
    if (raw == null || raw.isEmpty) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];
    final profiles = <SavedServerProfile>[];
    for (final item in decoded) {
      try {
        final profile = SavedServerProfile.fromJson(asMap(item));
        if (profile.serverUrl.isNotEmpty || profile.localServerUrl.isNotEmpty) {
          profiles.add(profile);
        }
      } catch (_) {
        // 单条记录坏掉不该连累其它服务器，跳过它继续解析。
      }
    }
    return profiles;
  }

  Future<List<SavedServerProfile>> _loadSavedServers() async {
    final profiles = _readSavedServersFromPrefs();
    if (profiles.isEmpty) return const [];
    // 索引里的每个 profile 都要访问钥匙串。iOS 上钥匙串调用是同步 IPC，
    // 逐个 await 请求会叠加成明显的启动延迟，所以并发读取。
    //
    // 任何一条读取失败都只影响它自己的密码，不能掀翻整份列表：覆盖安装换了
    // 签名、或设备刚启动还没解锁时钥匙串会整体拒绝访问，以前这里会把
    // savedServers 变成空列表，下次保存服务器时再把这张空表写回偏好表，
    // 用户的地址和账号就永久没了。
    var allHydrated = true;
    final hydrated = await Future.wait([
      for (final profile in profiles)
        _hydrateServerProfileSecrets(profile).catchError((Object _) {
          allHydrated = false;
          return profile;
        }),
    ]);
    // Only rewrite the index when every profile migrated cleanly. During a
    // keychain outage the inline legacy secrets may still be the only copy,
    // so leave the stored index untouched rather than dropping them.
    if (allHydrated) await _persistSavedServers(hydrated);
    return hydrated;
  }

  Future<SavedServerProfile> _hydrateServerProfileSecrets(
    SavedServerProfile profile,
  ) async {
    final key = _serverProfileSecretKey(profile);
    // 这里的任何失败都交给 _loadSavedServers 统一处理：它会保留偏好表里的
    // 原始索引不写回，否则带内联密码的旧记录会被无密码版本覆盖掉。
    final Map<String, String> record;
    final stored = await _credentials.read('$key.credentials');
    if (stored != null) {
      record = stored;
    } else {
      // 旧版本把密码拆成两个散键存在钥匙串里，读到后统一搬进整条记录。
      record = {
        'password':
            await _secureStorage.read(key: '$key.tr') ?? profile.password,
        'fnos_password': await _secureStorage.read(key: '$key.fnos') ??
            profile.fnosPassword,
        'cookie': profile.gatewayCookie,
        'access_code': profile.fnAccessCode,
      };
      await _credentials.write('$key.credentials', record);
    }
    try {
      // 确认整条记录已经可读，才清掉旧的散键。
      await _secureStorage.delete(key: '$key.tr');
      await _secureStorage.delete(key: '$key.fnos');
    } catch (_) {
      // 清理失败只会留下几个无用的旧键，不影响已经读到的密码。
    }
    return profile.copyWith(
      password: record['password'] ?? '',
      fnosPassword: record['fnos_password'] ?? '',
      gatewayCookie: record['cookie'] ?? '',
      fnAccessCode: record['access_code'] ?? '',
    );
  }

  Future<void> _storeServerProfileSecrets(
    SavedServerProfile profile, {
    SavedServerProfile? replaceProfile,
  }) async {
    final key = _serverProfileSecretKey(profile);
    await _credentials.write('$key.credentials', {
      'password': profile.password,
      'fnos_password': profile.fnosPassword,
      'cookie': profile.gatewayCookie,
      'access_code': profile.fnAccessCode,
    });
    if (replaceProfile != null &&
        _serverProfileSecretKey(replaceProfile) != key) {
      await _deleteServerProfileSecrets(replaceProfile);
    }
  }

  Future<void> _deleteServerProfileSecrets(SavedServerProfile profile) async {
    final key = _serverProfileSecretKey(profile);
    await _credentials.delete('$key.credentials');
    await _credentials.delete('$key.session');
    await _secureStorage.delete(key: '$key.tr');
    await _secureStorage.delete(key: '$key.fnos');
  }

  String _serverProfileSecretKey(SavedServerProfile profile) {
    final gatewayIdentity = _normalizedGatewayIdentity(profile.fnId);
    final identity = gatewayIdentity.isNotEmpty
        ? 'gateway|$gatewayIdentity|${profile.username}'
        : 'direct|${_normalizeOptionalServerUrl(profile.serverUrl)}|${_normalizeOptionalServerUrl(profile.localServerUrl)}|${profile.username}';
    final encoded = base64UrlEncode(utf8.encode(identity)).replaceAll('=', '');
    return 'server_profile.$encoded';
  }

  Future<void> _persistSavedServers(List<SavedServerProfile> profiles) async {
    await _prefs?.setString(
      'saved_servers',
      jsonEncode(profiles.map((item) => item.toJson()).toList()),
    );
  }

  Future<SavedServerProfile> _rememberProfile({
    required String server,
    String localServer = '',
    required String username,
    required String password,
    ServerProfileMode mode = ServerProfileMode.direct,
    String fnId = '',
    String fnosUsername = '',
    String fnosPassword = '',
    String gatewayCookie = '',
    String fnAccessCode = '',
    SavedServerProfile? replaceProfile,
  }) async {
    final gatewayHost = _gatewayHostForProfile(
      server: server,
      fnId: fnId,
      mode: mode,
    );
    final normalizedLocal = _normalizeOptionalServerUrl(localServer);
    final normalizedServer = gatewayHost == null
        ? _normalizeOptionalServerUrl(server)
        : FnosGateway.originUriForHost(gatewayHost).toString();
    final resolvedMode = gatewayHost == null
        ? ServerProfileMode.direct
        : ServerProfileMode.fnosGateway;
    final profile = SavedServerProfile(
      serverUrl: normalizedServer,
      localServerUrl: normalizedLocal,
      activeUrl: gatewayHost == null
          ? (normalizedLocal.isNotEmpty ? normalizedLocal : normalizedServer)
          : FnosGateway.appUriForHost(gatewayHost).toString(),
      username: username,
      password: password,
      label: username,
      mode: resolvedMode,
      fnId: gatewayHost ?? '',
      fnosUsername: resolvedMode == ServerProfileMode.fnosGateway
          ? fnosUsername.trim()
          : '',
      fnosPassword:
          resolvedMode == ServerProfileMode.fnosGateway ? fnosPassword : '',
      gatewayCookie: gatewayCookie,
      fnAccessCode:
          resolvedMode == ServerProfileMode.fnosGateway ? fnAccessCode : '',
    );
    await _saveServerProfile(profile, replaceProfile: replaceProfile);
    _notifyIfActive();
    return profile;
  }

  Future<void> _saveServerProfile(
    SavedServerProfile profile, {
    SavedServerProfile? replaceProfile,
  }) async {
    final normalizedServer = _normalizeOptionalServerUrl(profile.serverUrl);
    final normalizedLocal = _normalizeOptionalServerUrl(profile.localServerUrl);
    final normalizedReplaceServer = replaceProfile == null
        ? null
        : _normalizeOptionalServerUrl(replaceProfile.serverUrl);
    final normalizedReplaceLocal = replaceProfile == null
        ? null
        : _normalizeOptionalServerUrl(replaceProfile.localServerUrl);

    bool sameProfile(
      SavedServerProfile item,
      String? server,
      String? local,
      String username,
      ServerProfileMode mode,
      String fnId,
    ) {
      if (server == null || local == null) return false;
      final gatewayIdentity = _normalizedGatewayIdentity(fnId);
      final itemGatewayIdentity = _normalizedGatewayIdentity(item.fnId);
      if (_normalizeOptionalServerUrl(item.localServerUrl) != local ||
          item.username != username) {
        return false;
      }
      if (gatewayIdentity.isNotEmpty) {
        // Gateway profiles are one logical server; fnos.net and 5ddd.com
        // are only relay hosts chosen by fnOS, not different profiles.
        return itemGatewayIdentity == gatewayIdentity;
      }
      return itemGatewayIdentity.isEmpty &&
          item.mode == mode &&
          _normalizeOptionalServerUrl(item.serverUrl) == server;
    }

    final next = [
      profile.copyWith(
        serverUrl: normalizedServer,
        localServerUrl: normalizedLocal,
      ),
      ...savedServers.where(
        (item) {
          if (sameProfile(
            item,
            normalizedServer,
            normalizedLocal,
            profile.username,
            profile.mode,
            profile.fnId,
          )) {
            return false;
          }
          if (replaceProfile != null &&
              sameProfile(
                item,
                normalizedReplaceServer,
                normalizedReplaceLocal,
                replaceProfile.username,
                replaceProfile.mode,
                replaceProfile.fnId,
              )) {
            return false;
          }
          return true;
        },
      ),
    ];
    await _storeServerProfileSecrets(
      profile,
      replaceProfile: replaceProfile,
    );
    savedServers = next.take(8).toList();
    await _persistSavedServers(savedServers);
  }

  Future<void> _deleteProfile(SavedServerProfile profile) async {
    await _deleteServerProfileSecrets(profile);
    final normalizedServer = _normalizeOptionalServerUrl(profile.serverUrl);
    final normalizedLocal = _normalizeOptionalServerUrl(profile.localServerUrl);
    final gatewayIdentity = _normalizedGatewayIdentity(profile.fnId);
    savedServers = savedServers.where(
      (item) {
        final itemGatewayIdentity = _normalizedGatewayIdentity(item.fnId);
        if (_normalizeOptionalServerUrl(item.localServerUrl) !=
                normalizedLocal ||
            item.username != profile.username) {
          return true;
        }
        if (gatewayIdentity.isNotEmpty) {
          return itemGatewayIdentity != gatewayIdentity;
        }
        return itemGatewayIdentity.isNotEmpty ||
            item.mode != profile.mode ||
            _normalizeOptionalServerUrl(item.serverUrl) != normalizedServer;
      },
    ).toList();
    await _persistSavedServers(savedServers);
    _notifyIfActive();
  }
}
