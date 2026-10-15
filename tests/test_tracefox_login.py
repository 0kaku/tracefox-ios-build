import json
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'ci'))
from unsigned_build import configuration, unsigned_source_changes


class TraceFoxLoginTest(unittest.TestCase):
    values = {'TRACEFOX_ENABLE_LOGIN': '1', 'TRACEFOX_API_ID': '12345',
              'TRACEFOX_API_HASH': 'abcdef0123456789abcdef0123456789',
              'TRACEFOX_SERVER': 'https://archive.example.test', 'TRACEFOX_BOT': 'TraceFoxTestBot'}

    def test_login_config_requires_own_valid_credentials(self):
        with patch.dict(os.environ, self.values):
            config = configuration()
            self.assertEqual(config['bundle_id'], 'one.tracefox.telegram')
            self.assertEqual(config['api_id'], '12345')
            self.assertEqual(json.loads(config['sg_config'])['bot_username'], 'TraceFoxTestBot')
            self.assertNotIn(' ', config['sg_config'])

    def test_missing_or_invalid_values_fail_closed(self):
        for key, bad in [('TRACEFOX_API_ID', '1'), ('TRACEFOX_API_HASH', '0'*32),
                         ('TRACEFOX_API_HASH', ''), ('TRACEFOX_SERVER', 'http://example.test'),
                         ('TRACEFOX_SERVER', 'https://u:p@example.test'),
                         ('TRACEFOX_SERVER', 'https://example.test/path'),
                         ('TRACEFOX_BOT', 'bad/username')]:
            with self.subTest(key=key, bad=bad), patch.dict(os.environ, dict(self.values, **{key: bad})):
                with self.assertRaises(ValueError): configuration()

    def test_reversible_settings_patch_on_real_checkout(self):
        source = Path(os.environ.get('TRACEFOX_SOURCE', r'D:\TraceFoxBuild\tracefox-darkgram-ios'))
        if not source.exists(): self.skipTest('Pinned source is not checked out')
        with patch.dict(os.environ, self.values):
            changes = unsigned_source_changes(source)
        path = source / 'Swiftgram/SGSettingsUI/Sources/SGSettingsController.swift'
        original, modified = changes[path]
        self.assertEqual(path.read_text(encoding='utf-8'), original)
        self.assertIn('case .tracefoxArchive:', modified)
        self.assertIn('https://t.me/', modified)
        self.assertIn('"//Swiftgram/SGConfig:SGConfig"', changes[source/'Swiftgram/SGSettingsUI/BUILD'][1])


if __name__ == '__main__': unittest.main()
