from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'ci'))
from tracefox_temporary_media import temporary_media_changes

SOURCE = Path(r'D:\TraceFoxBuild\tracefox-darkgram-ios')


@unittest.skipUnless(SOURCE.is_dir(), 'Pinned checkout required')
class TemporaryMediaHooksTest(unittest.TestCase):
    def test_native_timer_and_read_paths_remain_and_capture_precedes_expiry(self):
        changes = temporary_media_changes(SOURCE)
        timer = SOURCE/'submodules/TelegramCore/Sources/State/ManagedAutoremoveMessageOperations.swift'
        before, after = changes[timer]
        self.assertEqual(after.replace('                        TraceFoxLocalArchive.captureDeleted(transaction: transaction, mediaBox: postbox.mediaBox, ids: [entry.messageId])\n',''), before)
        self.assertLess(after.index('TraceFoxLocalArchive.captureDeleted'), after.index('transaction.updateMessage(message.id'))
        self.assertIn('_internal_deleteMessages(transaction:', after)
        consume = SOURCE/'submodules/TelegramCore/Sources/TelegramEngine/Messages/MarkMessageContentAsConsumedInteractively.swift'
        before, after = changes[consume]
        self.assertEqual(before.count('TelegramMediaExpiredContent('), after.count('TelegramMediaExpiredContent('))
        self.assertIn('consumeDate: Int32?, mediaBox: MediaBox)', after)
        self.assertIn('TraceFoxLocalArchive.captureAvailable', after)
        for path, (original, replacement) in changes.items():
            self.assertEqual(path.read_text(encoding='utf-8'), original)
            self.assertNotIn('darkgramDontRead', replacement)

    def test_all_three_remote_callers_receive_account_media_box(self):
        changes = temporary_media_changes(SOURCE)
        callers = []
        for path, (_, modified) in changes.items():
            if path.name in ['AccountStateManagementUtils.swift','ProcessSecretChatIncomingDecryptedOperations.swift']:
                callers += [line for line in modified.splitlines() if 'markMessageContentAsConsumedRemotely(' in line]
        self.assertEqual(len(callers), 3)
        self.assertTrue(all('mediaBox: mediaBox)' in line for line in callers))


if __name__ == '__main__': unittest.main()
