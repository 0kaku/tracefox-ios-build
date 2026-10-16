from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'ci'))
from tracefox_privacy_hooks import privacy_presence_typing_changes

SOURCE = Path(r'D:\TraceFoxBuild\tracefox-darkgram-ios')

@unittest.skipUnless(SOURCE.is_dir(), 'Pinned source required')
class PrivacyHooksTest(unittest.TestCase):
    def test_network_rechecks_lazy_signal_before_constructing_request(self):
        path = SOURCE/'submodules/TelegramCore/Sources/Network/Network.swift'
        before, after = privacy_presence_typing_changes(SOURCE)[path]
        for name in ('requestWithAdditionalInfo', 'request'):
            part = after[after.index('    public func '+name+'<T>'):]
            self.assertLess(part.index('return Signal { subscriber in'),part.index('let privacy ='))
            self.assertLess(part.index('let privacy ='),part.index('let request = MTRequest()'))
            self.assertLess(part.index('subscriber.putCompletion()'),part.index('requestService.add(request)'))
            self.assertIn('request.setPayload(payload.makeData()',part)
        self.assertEqual(before.count('data.2.parse(Buffer(data: response))'),after.count('data.2.parse(Buffer(data: response))'))
        self.assertEqual(before.count('requestService.add(request)'),after.count('requestService.add(request)'))

    def test_presence_keeps_native_timer_and_offline_path(self):
        changes = privacy_presence_typing_changes(SOURCE)
        path = SOURCE/'submodules/TelegramCore/Sources/State/ManagedAccountPresence.swift'
        original, modified = changes[path]
        self.assertEqual(original.count('SignalKitTimer(timeout: 30.0'), modified.count('SignalKitTimer(timeout: 30.0'))
        self.assertIn('== .forceOffline ? .boolTrue : .boolFalse', modified)
        self.assertIn('request = self.network.request(Api.functions.account.updateStatus(offline: .boolTrue))', modified)
        self.assertEqual(path.read_text(encoding='utf-8'), original)

    def test_typing_guard_precedes_both_plain_and_encrypted_requests(self):
        changes = privacy_presence_typing_changes(SOURCE)
        path = SOURCE/'submodules/TelegramCore/Sources/State/ManagedLocalInputActivities.swift'
        original, modified = changes[path]
        guard = modified.index('TraceFoxPrivacyRuntime.decision')
        self.assertLess(guard, modified.index('Api.functions.messages.setTyping'))
        self.assertLess(guard, modified.index('Api.functions.messages.setEncryptedTyping'))
        self.assertIn('return .complete()', modified[guard:guard+150])
        self.assertEqual(path.read_text(encoding='utf-8'), original)

if __name__ == '__main__': unittest.main()
