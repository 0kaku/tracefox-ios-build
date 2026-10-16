"""Local ASGI contract test: actual Swift fixtures, in-memory DB, fake Telegram."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from datetime import timedelta

BACKEND = Path(r'D:\TheMurconBot')
FIXTURE = Path(r'D:\TraceFoxBuild\ios-ci-runs\38846150467\cloud-payload-fixtures.json')


@unittest.skipUnless(BACKEND.is_dir() and FIXTURE.is_file(), 'Local backend and exported Swift fixture required')
class SwiftBackendContractTest(unittest.IsolatedAsyncioTestCase):
    async def test_real_endpoint_accepts_swift_payloads_with_owner_isolation(self):
        sys.path.insert(0, str(BACKEND))
        import httpx
        from fastapi import FastAPI
        from app.android_bridge import build_router, token_hash
        from app.config import Settings
        from app.db import AndroidDevice, utcnow
        from app.service import BotService
        from tests.test_hardening import FakeTelegram, connection, memory_sessions

        rows = json.loads(FIXTURE.read_text(encoding='utf-8'))
        engine, sessions = await memory_sessions()
        fake = FakeTelegram()
        try:
            with tempfile.TemporaryDirectory() as folder:
                settings = Settings(bot_token='synthetic-test', media_storage_path=folder)
                async def user(): return {'id': 10}
                async def db():
                    async with sessions() as session: yield session
                app = FastAPI()
                app.include_router(build_router(BotService(fake, settings), settings, user, db))
                async with sessions() as session:
                    for owner in (10, 11):
                        account = connection(owner_id=owner, connection_id=f'contract-{owner}')
                        account.paid_until = utcnow() + timedelta(days=1)
                        session.add(account)
                        session.add(AndroidDevice(owner_id=owner, token_hash=token_hash(f'synthetic-{owner}'), expires_at=utcnow()+timedelta(days=1)))
                    await session.commit()
                headers = {'Authorization': 'Bearer synthetic-10'}
                other = {'Authorization': 'Bearer synthetic-11'}
                async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url='https://test.invalid') as client:
                    self.assertEqual((await client.post('/api/android/messages', json=rows[0])).status_code, 401)
                    ids = []
                    for row in rows:
                        response = await client.post('/api/android/messages', headers=headers, json=row)
                        self.assertEqual(response.status_code, 200)
                        self.assertTrue(response.json()['ok'])
                        ids.append(response.json()['archive_id'])
                    duplicate = await client.post('/api/android/messages', headers=headers, json=rows[0])
                    self.assertEqual(duplicate.json()['archive_id'], ids[0])
                    own = (await client.get('/api/android/archive', headers=headers)).json()['items']
                    foreign = (await client.get('/api/android/archive', headers=other)).json()['items']
                    self.assertEqual(len(own), 3)
                    self.assertEqual(foreign, [])
                    saved = next(item for item in own if item['id'] == ids[0])
                    self.assertTrue(saved['deleted'] and saved['temporary'] and saved['view_once'])
                    self.assertEqual(saved['ttl_seconds'], 2147483647)
                    other_save = await client.post('/api/android/messages', headers=other, json=rows[0])
                    self.assertNotEqual(other_save.json()['archive_id'], ids[0])
                    invalid = dict(rows[0], message_id=0)
                    self.assertEqual((await client.post('/api/android/messages', headers=headers, json=invalid)).status_code, 422)
                self.assertEqual(fake.calls, [])
                self.assertEqual(fake.messages, [])
        finally:
            await engine.dispose()


if __name__ == '__main__': unittest.main()
