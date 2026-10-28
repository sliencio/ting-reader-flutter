part of 'app_shell.dart';

class _MobileAdminOverlay extends StatelessWidget {
  const _MobileAdminOverlay({
    required this.go,
    required this.current,
    required this.onClose,
    required this.pluginPages,
    required this.activePluginPageId,
    required this.onOpenPluginPage,
  });

  final ValueChanged<AppDestination> go;
  final AppDestination current;
  final VoidCallback onClose;
  final List<ClientExtensionDescriptor> pluginPages;
  final String? activePluginPageId;
  final ValueChanged<ClientExtensionDescriptor> onOpenPluginPage;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClose,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                child: Container(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.46),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: _MobileDrawer(
              go: go,
              current: current,
              onClose: onClose,
              pluginPages: pluginPages,
              activePluginPageId: activePluginPageId,
              onOpenPluginPage: onOpenPluginPage,
            ),
          ),
          Positioned(
            right: 22,
            top: topInset + 12,
            child: Material(
              color: context.cardColor.withValues(alpha: 0.92),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: context.localeText('关闭', 'Close'),
                icon: Icon(
                  Icons.close_rounded,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                onPressed: onClose,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileDrawer extends StatelessWidget {
  const _MobileDrawer({
    required this.go,
    required this.current,
    required this.onClose,
    required this.pluginPages,
    required this.activePluginPageId,
    required this.onOpenPluginPage,
  });

  final ValueChanged<AppDestination> go;
  final AppDestination current;
  final VoidCallback onClose;
  final List<ClientExtensionDescriptor> pluginPages;
  final String? activePluginPageId;
  final ValueChanged<ClientExtensionDescriptor> onOpenPluginPage;

  @override
  Widget build(BuildContext context) {
    final appState = AppScope.appOf(context);
    final user = appState.user;
    final width = _drawerWidthFor(context);
    final l10n = context.l10n;
    if (appState.offlineMode) {
      return Drawer(
        width: width,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _GroupLabel(l10n.navOfflineMode),
                _MobileAdminTile(
                  icon: Icons.download_done_rounded,
                  label: l10n.navDownloads,
                  selected: true,
                  onTap: () {
                    onClose();
                    go(AppDestination.downloads);
                  },
                ),
                const Spacer(),
                _DrawerAccountCard(
                  user: user,
                  roleLabel: 'OFFLINE',
                  onLogout: () async {
                    onClose();
                    await appState.logout();
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Drawer(
      width: width,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    if (appState.isAdmin) ...[
                      _GroupLabel(l10n.navAdmin),
                      for (final entry in _navigationEntries(
                        context,
                        admin: true,
                      ))
                        _MobileAdminTile(
                          icon: entry.icon,
                          label: entry.label,
                          selected: _navigationSelected(
                            entry.destination,
                            current,
                          ),
                          onTap: () {
                            onClose();
                            go(entry.destination);
                          },
                        ),
                    ],
                    if (pluginPages.isNotEmpty) ...[
                      if (appState.isAdmin) const SizedBox(height: 22),
                      _GroupLabel(l10n.navPluginPages),
                      for (final extension in pluginPages)
                        _MobilePluginTile(
                          extension: extension,
                          selected: current == AppDestination.pluginPage &&
                              activePluginPageId == extension.id,
                          onTap: () {
                            onClose();
                            onOpenPluginPage(extension);
                          },
                        ),
                    ],
                    if (!appState.isAdmin && pluginPages.isEmpty)
                      EmptyState(
                        icon: Icons.admin_panel_settings_outlined,
                        title: l10n.navNoAdminEntry,
                        message: l10n.navMainMenuInBottom,
                      ),
                  ],
                ),
              ),
              _DrawerAccountCard(
                user: user,
                roleLabel: user?.isAdmin == true ? 'ADMINISTRATOR' : 'USER',
                onLogout: () async {
                  onClose();
                  await appState.logout();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _drawerWidthFor(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    if (screenWidth < 392) {
      return screenWidth * 0.92;
    }
    return 360;
  }
}

class _MobileAdminTile extends StatelessWidget {
  const _MobileAdminTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppColors.primary600 : Colors.transparent,
        elevation: selected ? 8 : 0,
        shadowColor: AppColors.primary500.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 24,
                  color: selected ? Colors.white : context.mutedText,
                ),
                const SizedBox(width: 18),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : context.mutedText,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobilePluginTile extends StatelessWidget {
  const _MobilePluginTile({
    required this.extension,
    required this.selected,
    required this.onTap,
  });

  final ClientExtensionDescriptor extension;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : context.mutedText;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppColors.primary600 : Colors.transparent,
        elevation: selected ? 8 : 0,
        shadowColor: AppColors.primary500.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                PluginExtensionIcon(
                  extension: extension,
                  size: 24,
                  color: foreground,
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Text(
                    extension.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: foreground, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawerAccountCard extends StatelessWidget {
  const _DrawerAccountCard({
    required this.user,
    required this.roleLabel,
    required this.onLogout,
  });

  final dynamic user;
  final String roleLabel;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    final username = (user?.username as String?) ?? '';
    return Container(
      padding: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.faintBorder)),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.isDark
              ? AppColors.slate800.withValues(alpha: 0.55)
              : AppColors.slate50,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.primary100,
              foregroundColor: AppColors.primary700,
              child: Text(
                username.isNotEmpty
                    ? username.substring(0, 1).toUpperCase()
                    : 'U',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    roleLabel,
                    style: TextStyle(
                      color: context.mutedText,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: context.l10n.navLogout,
              onPressed: onLogout,
              icon: const Icon(Icons.logout_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
