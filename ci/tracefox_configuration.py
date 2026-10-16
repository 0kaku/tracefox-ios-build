"""Validated login configuration and small, reversible TraceFox UI integration."""
import json
import os
import re
from pathlib import Path
from tracefox_temporary_media import temporary_media_changes
from tracefox_privacy_hooks import privacy_presence_typing_changes
from tracefox_read_hooks import privacy_read_changes
from urllib.parse import urlparse


def login_enabled():
    return os.environ.get('TRACEFOX_ENABLE_LOGIN') == '1'


def login_configuration(base):
    if not login_enabled():
        return base
    api_id = os.environ.get('TRACEFOX_API_ID', '')
    api_hash = os.environ.get('TRACEFOX_API_HASH', '')
    server = os.environ.get('TRACEFOX_SERVER', '').rstrip('/')
    bot = os.environ.get('TRACEFOX_BOT', '').lstrip('@')
    origin = urlparse(server)
    if not api_id.isdecimal() or int(api_id) <= 1 or int(api_id) > 2147483647:
        raise ValueError('Valid TraceFox API ID is required for login builds')
    if not re.fullmatch('[a-fA-F0-9]{32}', api_hash) or api_hash == '0' * 32:
        raise ValueError('Valid TraceFox API hash is required for login builds')
    if origin.scheme != 'https' or not origin.hostname or origin.username or origin.password or origin.path or origin.query or origin.fragment:
        raise ValueError('TraceFox server must be an HTTPS origin')
    if not re.fullmatch('[A-Za-z0-9_]{5,32}', bot) or not bot.lower().endswith('bot'):
        raise ValueError('Valid TraceFox bot username is required')
    return dict(base, bundle_id='one.tracefox.telegram', api_id=api_id, api_hash=api_hash,
                app_specific_url_scheme='tracefox', sg_config=json.dumps({
                    'api_url': server, 'webapp_url': server + '/app', 'bot_username': bot, 'iaps': []
                }, separators=(',', ':')))


def integration_changes(source):
    if not login_enabled():
        return {}
    path = source / 'Swiftgram/SGSettingsUI/Sources/SGSettingsController.swift'
    original = path.read_text(encoding='utf-8')
    replacements = {
        'import SGAPIToken': 'import SGAPIToken\nimport SGConfig',
        'private enum SGDisclosureLink: String {':
            'private enum SGDisclosureLink: String {\n    case tracefoxBot\n    case tracefoxArchive\n    case tracefoxLocalArchive\n    case tracefoxPrivacy\n    case tracefoxPairing',
        '    return filterSGItemListUIEntrires(entries: entries, by: state.searchQuery)':
            '    entries.append(.header(id: id.count, section: .other, text: "TraceFox", badge: nil))\n'
            '    entries.append(.disclosure(id: id.count, section: .other, link: .tracefoxBot, text: "Бот TraceFox"))\n'
            '    entries.append(.disclosure(id: id.count, section: .other, link: .tracefoxArchive, text: "Хмарний архів TraceFox"))\n'
            '    entries.append(.disclosure(id: id.count, section: .other, link: .tracefoxLocalArchive, text: "Локальний архів TraceFox"))\n'
            '    entries.append(.disclosure(id: id.count, section: .other, link: .tracefoxPrivacy, text: "Приватність TraceFox"))\n'
            '    entries.append(.disclosure(id: id.count, section: .other, link: .tracefoxPairing, text: "Прив’язка акаунта до бота"))\n'
            '    entries.append(.notice(id: id.count, section: .other, text: "Локальні копії, параметри приватності та прив’язка акаунта. Синхронізацію локального архіву з хмарою ще не підключено."))\n'
            '    return filterSGItemListUIEntrires(entries: entries, by: state.searchQuery)',
        '    }, openDisclosureLink: { link in\n        switch (link) {':
            '    }, openDisclosureLink: { link in\n        switch (link) {\n'
            '            case .tracefoxBot:\n'
            '                context.sharedContext.applicationBindings.openUrl("https://t.me/" + SG_CONFIG.botUsername)\n'
            '            case .tracefoxArchive:\n'
            '                context.sharedContext.applicationBindings.openUrl("https://t.me/" + SG_CONFIG.botUsername + "?startapp=archive")\n'
            '            case .tracefoxLocalArchive:\n'
            '                pushControllerImpl?(traceFoxArchiveController(context: context))\n'
            '            case .tracefoxPrivacy:\n'
            '                pushControllerImpl?(traceFoxPrivacyController(context: context))\n'
            '            case .tracefoxPairing:\n'
            '                pushControllerImpl?(traceFoxBotPairingController(context: context))',
        'title: .text("Swiftgram")': 'title: .text("TraceFox")',
    }
    modified = original
    for old, new in replacements.items():
        if modified.count(old) != 1:
            raise RuntimeError('TraceFox settings integration anchor changed')
        modified = modified.replace(old, new)
    changes = {path: (original, modified)}
    recipe = Path(__file__).resolve().parent
    overlays = {
        'TraceFoxCloudArchiveBridge.swift': 'submodules/TelegramCore/Sources/Swiftgram/TraceFoxCloudArchiveBridge.swift',
        'TraceFoxCloudArchiveSender.swift': 'submodules/TelegramCore/Sources/Swiftgram/TraceFoxCloudArchiveSender.swift',
        'TraceFoxCloudArchiveQueue.swift': 'submodules/TelegramCore/Sources/Swiftgram/TraceFoxCloudArchiveQueue.swift',
        'TraceFoxCloudArchivePayload.swift': 'submodules/TelegramCore/Sources/Swiftgram/TraceFoxCloudArchivePayload.swift',
        'TraceFoxCloudArchiveIdentity.swift': 'submodules/TelegramCore/Sources/Swiftgram/TraceFoxCloudArchiveIdentity.swift',
        'TraceFoxBotPairingController.swift': 'Swiftgram/SGSettingsUI/Sources/TraceFoxBotPairingController.swift',
        'TraceFoxBotPairingCoordinator.swift': 'submodules/TelegramCore/Sources/Swiftgram/TraceFoxBotPairingCoordinator.swift',
        'TraceFoxBotLinkClient.swift': 'submodules/TelegramCore/Sources/Swiftgram/TraceFoxBotLinkClient.swift',
        'TraceFoxBotPairingAttempt.swift': 'submodules/TelegramCore/Sources/Swiftgram/TraceFoxBotPairingAttempt.swift',
        'TraceFoxBotCredentialStore.swift': 'submodules/TelegramCore/Sources/Swiftgram/TraceFoxBotCredentialStore.swift',
        'TraceFoxBotLinkProtocol.swift': 'submodules/TelegramCore/Sources/Swiftgram/TraceFoxBotLinkProtocol.swift',
        'TraceFoxArchiveStore.swift': 'submodules/TelegramCore/Sources/Swiftgram/TraceFoxArchiveStore.swift',
        'TraceFoxLocalArchive.swift': 'submodules/TelegramCore/Sources/Swiftgram/TraceFoxLocalArchive.swift',
        'TraceFoxArchiveController.swift': 'Swiftgram/SGSettingsUI/Sources/TraceFoxArchiveController.swift',
        'TraceFoxPrivacyPolicy.swift': 'submodules/TelegramCore/Sources/Swiftgram/TraceFoxPrivacyPolicy.swift',
        'TraceFoxPrivacyRuntime.swift': 'submodules/TelegramCore/Sources/Swiftgram/TraceFoxPrivacyRuntime.swift',
        'TraceFoxPrivacyControl.swift': 'submodules/TelegramCore/Sources/Swiftgram/TraceFoxPrivacyControl.swift',
        'TraceFoxPrivacyController.swift': 'Swiftgram/SGSettingsUI/Sources/TraceFoxPrivacyController.swift',
    }
    for name, target in overlays.items():
        target_path = source / target
        if target_path.exists():
            raise RuntimeError('Unexpected existing TraceFox overlay: ' + target)
        changes[target_path] = (None, (recipe / name).read_text(encoding='utf-8'))
    deletion = source / 'submodules/TelegramCore/Sources/TelegramEngine/Messages/DeleteMessages.swift'
    original = deletion.read_text(encoding='utf-8')
    signature = 'public func _internal_deleteMessages(transaction: Transaction, mediaBox: MediaBox, ids: [MessageId], deleteMedia: Bool = true, manualAddMessageThreadStatsDifference: ((MessageThreadKey, Int, Int) -> Void)? = nil) {\n'
    if original.count(signature) != 1:
        raise RuntimeError('Native delete-messages entry point changed')
    changes[deletion] = (original, original.replace(signature, signature +
        '    TraceFoxLocalArchive.captureDeleted(transaction: transaction, mediaBox: mediaBox, ids: ids)\n'))
    changes.update(temporary_media_changes(source))
    edit_file = source / 'submodules/TelegramCore/Sources/State/AccountStateManagementUtils.swift'
    original, modified = changes[edit_file]
    edit_anchor = '            case let .EditMessage(id, message):\n                var generatedEvent:'
    if modified.count(edit_anchor) != 1:
        raise RuntimeError('Native edit-message replay entry changed')
    modified = modified.replace(edit_anchor,
        '            case let .EditMessage(id, message):\n'
        '                TraceFoxLocalArchive.captureTextEdit(transaction: transaction, mediaBox: mediaBox, id: id, updatedText: message.text, updatedHasMedia: !message.media.isEmpty)\n'
        '                var generatedEvent:')
    changes[edit_file] = (original, modified)
    changes.update(privacy_presence_typing_changes(source))
    changes.update(privacy_read_changes(source, changes))
    cleanup = source/'submodules/TelegramCore/Sources/Account/AccountManager.swift'
    original = cleanup.read_text(encoding='utf-8')
    anchor = '    Logger.shared.log("AccountManager", "logoutFromAccount \\(id)")\n    return accountManager.transaction { transaction -> Void in\n'
    if original.count(anchor) != 1: raise RuntimeError('Logout account-record entry changed')
    modified = original.replace(anchor, anchor + '        try? TraceFoxBotCredentialStore().removeAccountRecord(id.int64)\n')
    anchor = '    return accountWithId(accountManager: accountManager, networkArguments: networkArguments, id: id, encryptionParameters: encryptionParameters, supplementary: true, isSupportUser: isSupportUser, rootPath: rootPath, beginWithTestingEnvironment: beginWithTestingEnvironment, backupData: nil, auxiliaryMethods: auxiliaryMethods)'
    if modified.count(anchor) != 1: raise RuntimeError('Account cleanup authorization entry changed')
    modified = modified.replace(anchor, '    try? TraceFoxBotCredentialStore().removeAccountRecord(id.int64)\n' + anchor)
    changes[cleanup] = (original, modified)
    return changes
