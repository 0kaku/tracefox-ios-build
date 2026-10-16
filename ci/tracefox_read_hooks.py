"""Suppress read operations locally without synthesizing Telegram RPC responses."""
import re


def privacy_read_changes(source, prior):
    changes = {}

    def read(path):
        if path in changes: return changes[path]
        if path in prior: return prior[path]
        original = path.read_text(encoding='utf-8')
        return original, original

    guards = [
        ('State/ManagedSynchronizeViewStoriesOperations.swift', 'pushStoriesAreSeen', 'stories.readStories', '.complete()'),
        ('State/SynchronizePeerReadState.swift', 'pushPeerReadState', 'messages.readHistory', '.single(readState)'),
        ('State/ManagedSynchronizeConsumeMessageContentsOperations.swift', 'synchronizeConsumeMessageContents', 'messages.readMessageContents', '.complete()'),
        ('State/ManagedConsumePersonalMessagesActions.swift', 'synchronizeConsumeMessageContents', 'messages.readMessageContents', '.complete()'),
        ('State/ManagedConsumePersonalMessagesActions.swift', 'synchronizeReadMessageReactions', 'messages.readReactions', '.complete()'),
        ('State/ManagedSynchronizeMarkAllUnseenPersonalMessagesOperations.swift', 'synchronizeMarkAllUnseen', 'messages.readMentions', '.complete()'),
        ('State/ManagedSynchronizeMarkAllUnseenPersonalMessagesOperations.swift', 'synchronizeMarkAllUnseenReactions', 'messages.readReactions', '.complete()'),
        ('TelegramEngine/Messages/MarkAllChatsAsRead.swift', '_internal_markAllChatsAsRead', 'messages.readHistory', '.complete()'),
    ]
    for filename, function, method, completion in guards:
        path = source/'submodules/TelegramCore/Sources'/filename
        original, modified = read(path)
        result_type = 'PeerReadState, ' if function == 'pushPeerReadState' else 'Void, '
        pattern = re.compile(r'(?m)^(?:private )?func ' + re.escape(function) + r'\([^\n]+\) -> Signal<' + result_type + r'[^\n]+ \{\n')
        if len(pattern.findall(modified)) != 1:
            raise RuntimeError('Native read operation entry changed: ' + function)
        guard = '    if TraceFoxPrivacyRuntime.decision(network: network, function: "' + method + '") == .suppress { return ' + completion + ' }\n'
        modified = pattern.sub(lambda match: match[0] + guard, modified)
        changes[path] = (original, modified)

    consume = source/'submodules/TelegramCore/Sources/TelegramEngine/Messages/MarkMessageContentAsConsumedInteractively.swift'
    original, modified = read(consume)
    anchor = '            if message.containsSecretMedia { TraceFoxLocalArchive.captureAvailable(transaction: transaction, mediaBox: postbox.mediaBox, ids: [messageId]) }\n'
    if modified.count(anchor) != 1: raise RuntimeError('Interactive archive-before-read anchor changed')
    changes[consume] = (original, modified.replace(anchor, anchor +
        '            if TraceFoxPrivacyRuntime.decision(mediaBoxPath: postbox.mediaBox.basePath, function: "messages.readMessageContents") == .suppress { return }\n'))

    tracker = source/'submodules/TelegramCore/Sources/State/AccountViewTracker.swift'
    original, modified = read(tracker)
    anchor = 'let signal = (account.postbox.transaction { transaction -> Signal<Void, NoError> in\n                            if let peer = transaction.getPeer(peerId), let inputPeer = apiInputPeer(peer) {\n                                let request: Signal<Bool, MTRpcError>'
    if modified.count(anchor) != 1: raise RuntimeError('Direct content-read tracker entry changed')
    replacement = anchor.replace('                            if let peer',
        '                            if TraceFoxPrivacyRuntime.decision(network: account.network, function: "messages.readMessageContents") == .suppress { return .complete() }\n                            if let peer', 1)
    changes[tracker] = (original, modified.replace(anchor, replacement))

    secret = source/'submodules/TelegramCore/Sources/State/ManagedSecretChatOutgoingOperations.swift'
    original, modified = read(secret)
    anchor = 'return sendServiceActionMessage(postbox: postbox, network: network, peerId: entry.peerId, action: .readMessageContents(layer: layer, actionGloballyUniqueId: actionGloballyUniqueId, globallyUniqueIds: globallyUniqueIds), tagLocalIndex: entry.tagLocalIndex, wasDelivered: operation.delivered)'
    if modified.count(anchor) != 1: raise RuntimeError('Queued encrypted read-service sender changed')
    replacement = '''let action: SecretMessageAction
                                    if TraceFoxPrivacyRuntime.decision(network: network, function: "messages.sendEncryptedService", isSecretReadService: true) == .suppress {
                                        if let sequenceLayer = SecretChatSequenceBasedLayer(rawValue: layer.rawValue) {
                                            action = .noop(layer: sequenceLayer, actionGloballyUniqueId: actionGloballyUniqueId)
                                        } else {
                                            action = .readMessageContents(layer: layer, actionGloballyUniqueId: actionGloballyUniqueId, globallyUniqueIds: [])
                                        }
                                    } else {
                                        action = .readMessageContents(layer: layer, actionGloballyUniqueId: actionGloballyUniqueId, globallyUniqueIds: globallyUniqueIds)
                                    }
                                    return sendServiceActionMessage(postbox: postbox, network: network, peerId: entry.peerId, action: action, tagLocalIndex: entry.tagLocalIndex, wasDelivered: operation.delivered)'''
    changes[secret] = (original, modified.replace(anchor, replacement))
    discussion = source/'submodules/TelegramCore/Sources/TelegramEngine/Messages/ApplyMaxReadIndexInteractively.swift'
    original, modified = read(discussion)
    for method in ('readDiscussion', 'readSavedHistory'):
        pattern = re.compile(r'(?m)^( +)(let _ = network\.request\(Api\.functions\.messages\.' + method + r'\([^\n]+\)\.start\(\))$')
        if len(pattern.findall(modified)) != 3:
            raise RuntimeError('Direct thread read calls changed: ' + method)
        modified = pattern.sub(lambda match: match[1] + 'if TraceFoxPrivacyRuntime.decision(network: network, function: "messages.' + method + '") != .suppress {\n' + match[1] + '    ' + match[2] + '\n' + match[1] + '}', modified)
    changes[discussion] = (original, modified)

    reply = source/'submodules/TelegramCore/Sources/TelegramEngine/Messages/ReplyThreadHistory.swift'
    original, modified = read(reply)
    anchor = '            if let subPeerId {\n                let signal = strongSelf.account.network.request(Api.functions.messages.readSavedHistory'
    if modified.count(anchor) != 1: raise RuntimeError('Reply thread read sender changed')
    changes[reply] = (original, modified.replace(anchor,
        '            if TraceFoxPrivacyRuntime.decision(network: strongSelf.account.network, function: "messages.readDiscussion") == .suppress { return }\n' + anchor))

    stories = source/'submodules/TelegramCore/Sources/TelegramEngine/Messages/Stories.swift'
    original, modified = read(stories)
    anchor = '            return account.network.request(Api.functions.stories.incrementStoryViews(peer: inputPeer, id: [id]))'
    if modified.count(anchor) != 1: raise RuntimeError('Pinned story view sender changed')
    changes[stories] = (original, modified.replace(anchor,
        '            if TraceFoxPrivacyRuntime.decision(network: account.network, function: "stories.incrementStoryViews") == .suppress { return .complete() }\n' + anchor))
    return changes
