from pathlib import Path
import os
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'ci'))
from unsigned_build import unsigned_source_changes

SOURCE = Path(r'D:\TraceFoxBuild\tracefox-darkgram-ios')

@unittest.skipUnless(SOURCE.is_dir(), 'Pinned source required')
class ReadHooksTest(unittest.TestCase):
    def test_direct_thread_receipts_preserve_local_updates(self):
        path=SOURCE/'submodules/TelegramCore/Sources/TelegramEngine/Messages/ApplyMaxReadIndexInteractively.swift'
        before,after=self.changes()[path]
        for method in ('readDiscussion','readSavedHistory'):
            self.assertEqual(after.count('function: "messages.'+method+'") != .suppress'),3)
            self.assertEqual(before.count('Api.functions.messages.'+method),after.count('Api.functions.messages.'+method))
        self.assertEqual(before.count('transaction.'),after.count('transaction.'))

    def test_reply_thread_preserves_local_count_before_suppression(self):
        path=SOURCE/'submodules/TelegramCore/Sources/TelegramEngine/Messages/ReplyThreadHistory.swift'
        before,after=self.changes()[path]
        guard='if TraceFoxPrivacyRuntime.decision(network: strongSelf.account.network'
        self.assertLess(after.index('strongSelf.unreadCountValue = unreadCountValue'),after.index(guard))
        self.assertLess(after.index(guard),after.index('Api.functions.messages.readSavedHistory'))
        self.assertLess(after.index(guard),after.index('Api.functions.messages.readDiscussion'))
        self.assertEqual(before.count('transaction.'),after.count('transaction.'))

    def test_story_receipts_keep_queue_cleanup(self):
        path=SOURCE/'submodules/TelegramCore/Sources/State/ManagedSynchronizeViewStoriesOperations.swift'
        before,after=self.changes()[path]
        self.assertIn('function: "stories.readStories") == .suppress',after)
        self.assertEqual(before.count('operationLogRemoveEntry'),after.count('operationLogRemoveEntry'))
        path=SOURCE/'submodules/TelegramCore/Sources/TelegramEngine/Messages/Stories.swift'
        before,after=self.changes()[path]
        self.assertIn('function: "stories.incrementStoryViews") == .suppress',after)
        self.assertEqual(before.count('transaction.'),after.count('transaction.'))

    def changes(self):
        with patch.dict(os.environ, {'TRACEFOX_ENABLE_LOGIN':'1','TRACEFOX_API_ID':'12345','TRACEFOX_API_HASH':'abcdef0123456789abcdef0123456789','TRACEFOX_SERVER':'https://archive.example.test','TRACEFOX_BOT':'TraceFoxTestBot'}):
            return unsigned_source_changes(SOURCE)

    def test_archive_precedes_local_read_suppression(self):
        path=SOURCE/'submodules/TelegramCore/Sources/TelegramEngine/Messages/MarkMessageContentAsConsumedInteractively.swift'
        text=self.changes()[path][1]
        self.assertLess(text.index('TraceFoxLocalArchive.captureAvailable'),text.index('TraceFoxPrivacyRuntime.decision(mediaBoxPath:'))
        self.assertLess(text.index('TraceFoxPrivacyRuntime.decision(mediaBoxPath:'),text.index('var updateMessage = false'))

    def test_suppressed_workers_keep_native_pending_operation_cleanup(self):
        for name, cleanup in [('ManagedSynchronizeConsumeMessageContentsOperations.swift','operationLogRemoveEntry'),
                              ('ManagedConsumePersonalMessagesActions.swift','setPendingMessageAction'),
                              ('ManagedSynchronizeMarkAllUnseenPersonalMessagesOperations.swift','operationLogRemoveEntry')]:
            path=SOURCE/'submodules/TelegramCore/Sources/State'/name
            original,modified=self.changes()[path]
            self.assertIn('== .suppress { return .complete() }',modified)
            self.assertEqual(original.count(cleanup),modified.count(cleanup))
            self.assertEqual(original.count('then(postbox.transaction'),modified.count('then(postbox.transaction'))

    def test_secret_queued_read_uses_native_noop_and_keeps_delivery_path(self):
        path=SOURCE/'submodules/TelegramCore/Sources/State/ManagedSecretChatOutgoingOperations.swift'
        before,after=self.changes()[path]
        self.assertIn('isSecretReadService: true',after)
        self.assertIn('SecretChatSequenceBasedLayer(rawValue: layer.rawValue)',after)
        self.assertIn('.noop(layer: sequenceLayer, actionGloballyUniqueId: actionGloballyUniqueId)',after)
        self.assertIn('action = .readMessageContents(layer: layer, actionGloballyUniqueId: actionGloballyUniqueId, globallyUniqueIds: [])',after)
        self.assertEqual(before.count('tagLocalIndex: entry.tagLocalIndex, wasDelivered: operation.delivered)'),after.count('tagLocalIndex: entry.tagLocalIndex, wasDelivered: operation.delivered)'))

if __name__ == '__main__': unittest.main()
