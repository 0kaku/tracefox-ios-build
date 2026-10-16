"""Initial privacy call-site patches. Read/service-message hooks remain separate."""


def privacy_presence_typing_changes(source):
    changes = {}
    presence = source/'submodules/TelegramCore/Sources/State/ManagedAccountPresence.swift'
    original = presence.read_text(encoding='utf-8')
    old = 'request = self.network.request(Api.functions.account.updateStatus(offline: .boolFalse))'
    new = 'request = self.network.request(Api.functions.account.updateStatus(offline: TraceFoxPrivacyRuntime.decision(network: self.network, function: "account.updateStatus") == .forceOffline ? .boolTrue : .boolFalse))'
    if original.count(old) != 1:
        raise RuntimeError('Native online-presence call changed')
    changes[presence] = (original, original.replace(old, new))

    typing = source/'submodules/TelegramCore/Sources/State/ManagedLocalInputActivities.swift'
    original = typing.read_text(encoding='utf-8')
    signature = 'private func requestActivity(postbox: Postbox, network: Network, accountPeerId: PeerId, peerId: PeerId, threadId: Int64?, activity: PeerInputActivity?) -> Signal<Void, NoError> {\n    return postbox.transaction { transaction -> Signal<Void, NoError> in\n'
    if original.count(signature) != 1:
        raise RuntimeError('Native typing-activity entry changed')
    changes[typing] = (original, original.replace(signature, signature +
        '        if TraceFoxPrivacyRuntime.decision(network: network, function: "messages.setTyping") == .suppress { return .complete() }\n'))

    network = source/'submodules/TelegramCore/Sources/Network/Network.swift'
    original = network.read_text(encoding='utf-8')
    modified = original
    # Recheck when a lazy Signal is subscribed, not only when its payload is built.
    # The native parser remains intact; suppressed calls complete without a result.
    for function in ('requestWithAdditionalInfo', 'request'):
        start = modified.index('    public func ' + function + '<T>')
        anchor = '        return Signal { subscriber in\n            let request = MTRequest()'
        index = modified.index(anchor, start)
        replacement = ('        return Signal { subscriber in\n'
            '            let privacy = TraceFoxPrivacyRuntime.decision(network: self, function: data.0.name)\n'
            '            if privacy == .suppress {\n'
            '                subscriber.putCompletion()\n'
            '                return EmptyDisposable\n'
            '            }\n'
            '            let payload = privacy == .forceOffline ? Api.functions.account.updateStatus(offline: .boolTrue).1 : data.1\n'
            '            let request = MTRequest()')
        modified = modified[:index] + modified[index:].replace(anchor, replacement, 1)
        payload = 'request.setPayload(data.1.makeData() as Data'
        index = modified.index(payload, index)
        modified = modified[:index] + modified[index:].replace(payload, 'request.setPayload(payload.makeData() as Data', 1)
    changes[network] = (original, modified)
    return changes
