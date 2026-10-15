"""Regress the pinned BuildConfig rule splitting JSON into compiler arguments."""
import json
from pathlib import Path
import shlex
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ci"))
from unsigned_build import configuration


def compiler_arguments(sg_config):
    # Exact copts expression from pinned submodules/BuildConfig/BUILD.
    return shlex.split("-DAPP_SG_CONFIG=\\\"{}\\\"".format(sg_config.replace('"', '\\\\\\"')))


class ConfigurationTest(unittest.TestCase):
    def test_json_remains_one_compiler_argument(self):
        value = configuration()["sg_config"]
        args = compiler_arguments(value)
        self.assertEqual(len(args), 1)
        self.assertTrue(args[0].startswith("-DAPP_SG_CONFIG="))
        self.assertEqual(json.loads(value)["bot_username"], "tracefox_build_test")

    def test_previous_whitespace_reproduces_failure(self):
        spaced = json.dumps(json.loads(configuration()["sg_config"]))
        self.assertGreater(len(compiler_arguments(spaced)), 1)


if __name__ == "__main__":
    unittest.main()
