"""Preserve native read/timer behavior while retaining available media first."""


def temporary_media_changes(source):
    changes = {}
    timer = source / 'submodules/TelegramCore/Sources/State/ManagedAutoremoveMessageOperations.swift'
    original = timer.read_text(encoding='utf-8')
    anchor = '                    if let message = transaction.getMessage(entry.messageId) {\n'
    if original.count(anchor) != 1:
        raise RuntimeError('Native autoremove timer entry changed')
    changes[timer] = (original, original.replace(anchor, anchor +
        '                        TraceFoxLocalArchive.captureDeleted(transaction: transaction, mediaBox: postbox.mediaBox, ids: [entry.messageId])\n'))

    consume = source / 'submodules/TelegramCore/Sources/TelegramEngine/Messages/MarkMessageContentAsConsumedInteractively.swift'
    original = consume.read_text(encoding='utf-8')
    local_anchor = '        if let message = transaction.getMessage(messageId), message.flags.contains(.Incoming) {\n'
    remote_signature = 'func markMessageContentAsConsumedRemotely(transaction: Transaction, messageId: MessageId, consumeDate: Int32?) {'
    if original.count(local_anchor) != 1 or original.count(remote_signature) != 1:
        raise RuntimeError('Native media consumption entry changed')
    modified = original.replace(local_anchor, local_anchor +
        '            if message.containsSecretMedia { TraceFoxLocalArchive.captureAvailable(transaction: transaction, mediaBox: postbox.mediaBox, ids: [messageId]) }\n')
    modified = modified.replace(remote_signature, remote_signature.replace('consumeDate: Int32?)', 'consumeDate: Int32?, mediaBox: MediaBox)'))
    local, remote = modified.split('func markMessageContentAsConsumedRemotely', 1)
    remote_anchor = '        if updateMessage {\n            transaction.updateMessage(message.id, update: { currentMessage in'
    if remote.count(remote_anchor) != 1:
        raise RuntimeError('Remote media expiry replacement changed')
    remote = remote.replace(remote_anchor,
        '        if updateMessage {\n'
        '            if updatedMedia.contains(where: { $0 is TelegramMediaExpiredContent }) {\n'
        '                TraceFoxLocalArchive.captureDeleted(transaction: transaction, mediaBox: mediaBox, ids: [messageId])\n'
        '            } else if message.containsSecretMedia {\n'
        '                TraceFoxLocalArchive.captureAvailable(transaction: transaction, mediaBox: mediaBox, ids: [messageId])\n'
        '            }\n'
        '            transaction.updateMessage(message.id, update: { currentMessage in')
    changes[consume] = (original, local + 'func markMessageContentAsConsumedRemotely' + remote)

    for filename, suffix, expected in [
        ('AccountStateManagementUtils.swift', 'date', 2),
        ('ProcessSecretChatIncomingDecryptedOperations.swift', 'nil', 1),
    ]:
        path = source / 'submodules/TelegramCore/Sources/State' / filename
        original = path.read_text(encoding='utf-8')
        lines = original.splitlines(keepends=True)
        count = 0
        for index, line in enumerate(lines):
            if 'markMessageContentAsConsumedRemotely(' in line:
                old = 'consumeDate: ' + suffix + ')'
                if line.count(old) != 1:
                    raise RuntimeError('Unexpected media consumption caller: ' + filename)
                lines[index] = line.replace(old, 'consumeDate: ' + suffix + ', mediaBox: mediaBox)')
                count += 1
        if count != expected:
            raise RuntimeError('Native media consumption caller count changed')
        changes[path] = (original, ''.join(lines))
    return changes
