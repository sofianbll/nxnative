"""Public Nextendo service profiles (dm/tools/nextendo_services.py), after NX-Port-Studio's test (MIT); no account state, no network."""
import base64
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('nextendo_services', REPO / 'dm/tools/nextendo_services.py')
assert spec is not None and spec.loader is not None
n = importlib.util.module_from_spec(spec); spec.loader.exec_module(n)
WONDER = '010015100b514000'
ZA = '0100f43008c44000'
VP = 'v3-lp1.vp.n.srv.nintendo.net'


class NextendoServicesTests(unittest.TestCase):
    def test_za_only_trusts_its_dedicated_ca_for_its_exact_npln_host(self):
        value = n.contract(REPO); ca = b'synthetic provider'; dedicated = b'synthetic dedicated CA'
        value['provider']['caSHA256'] = hashlib.sha256(ca).hexdigest()
        authority = value['serviceCAs']['legends-za']
        digest = authority['caSHA256'] = hashlib.sha256(dedicated).hexdigest()
        filename = digest + '.der'
        g3 = b'synthetic NPLN G3 CA'; npln = value['serviceCAs']['npln-class2-g3']
        g3_digest = npln['caSHA256'] = hashlib.sha256(g3).hexdigest()
        mk8 = '0100152000022000'
        base = dict(value, titles={k: v for k, v in value['titles'].items() if k != ZA})
        self.assertEqual(n.rules(value, mk8), n.rules(base, mk8))
        def pem(data):
            return b'-----BEGIN CERTIFICATE-----\n' + base64.b64encode(data) + b'\n-----END CERTIFICATE-----'
        with tempfile.TemporaryDirectory() as folder, patch.object(n.Path, 'home', return_value=Path(folder)), patch.object(n, 'contract', return_value=value):
            root = Path(folder)
            data_by_url = {authority['caURL']: dedicated, npln['caURL']: g3}
            with patch.object(n.urllib.request, 'urlopen', side_effect=lambda request, **_: io.BytesIO(pem(data_by_url[request.full_url]))) as fetch:
                other = n.prepare(REPO, mk8, root / 'mk8', ca=ca)
                self.assertFalse((other / filename).exists())
                self.assertFalse((other / (g3_digest + '.der')).exists())
                out = n.prepare(REPO, ZA, root / 'za', ca=ca)
                self.assertCountEqual([call.args[0].full_url for call in fetch.call_args_list], list(data_by_url))
            rows = [r.split('\t') for r in (out / 'routes.tsv').read_text().splitlines()[1:]]
            self.assertEqual([r for r in rows if r[4] == filename], [[
                'exact', 't-4e44e7a0-lp1.lp1.t.npln.srv.nintendo.net', value['provider']['server'], '@host', filename, digest, ZA + ':2']])
            self.assertEqual([r for r in rows if r[4] == g3_digest + '.der'], [[
                'exact', VP, value['provider']['server'], '@host', g3_digest + '.der', g3_digest]])
            self.assertEqual(next(r[4] for r in rows if r[1] == 'nintendo.net'), 'provider-ca.der')
            manifest = json.loads((out / 'manifest.json').read_text())
            self.assertEqual(manifest['files'][filename], digest)
            self.assertIs(manifest['bcat'], True)
            self.assertNotIn('bcat', json.loads((other / 'manifest.json').read_text()))
            self.assertEqual((out / filename).read_bytes(), dedicated)
            cached = root / 'Library/Application Support/nxnative/nextendo' / ('public-' + filename)
            self.assertEqual(cached.stat().st_mode & 0o777, 0o600)
            with patch.object(n.urllib.request, 'urlopen', side_effect=AssertionError('unexpected download')):
                n.prepare(REPO, ZA, root / 'cached', ca=ca)
            authority['caSHA256'] = '0' * 64
            with patch.object(n.urllib.request, 'urlopen', return_value=io.BytesIO(pem(dedicated))), self.assertRaisesRegex(ValueError, 'integrity'):
                n.prepare(REPO, ZA, root / 'bad', ca=ca)
            self.assertFalse((root / 'bad').exists())

    def test_shared_families_and_title_scoped_services(self):
        value = n.contract(REPO)
        self.assertIn('suffix\tdemonware.net\t', n.rules(value, '01001b300b9be000'))
        self.assertIn('api.epicgames.dev', n.rules(value, '0100ab401f136000'))
        self.assertNotIn('api.epicgames.dev', n.rules(value, WONDER))
        self.assertIn('label\tnncs2-*.', n.rules(value, WONDER))
        for title in ('0' * 16, 'bad', '../0000000000000'):
            with self.assertRaises(ValueError): n.rules(value, title)

    def test_profile_files_match_their_manifest(self):
        with tempfile.TemporaryDirectory() as folder:
            ca = b'synthetic public CA bytes'; value = n.contract(REPO)
            value['provider']['caSHA256'] = hashlib.sha256(ca).hexdigest()
            with patch.object(n, 'contract', return_value=value):
                out = n.prepare(REPO, WONDER, Path(folder) / 'profile', ca=ca)
            manifest = json.loads((out / 'manifest.json').read_text())
            self.assertEqual(manifest['identity'], {'account': 'pid', 'friends': 'baas'})   # hle_nextendo_api_apple.m reads it
            routes = (out / 'routes.tsv').read_bytes()
            self.assertTrue(routes.startswith(b'NXNEXTENDO_ROUTES_2\n'))
            pins = {row.split('\t')[4] for row in routes.decode().splitlines()[1:] if row.startswith('pinned-exact\t')}
            expected = {'routes.tsv': hashlib.sha256(routes).hexdigest(), 'provider-ca.der': hashlib.sha256(ca).hexdigest()}
            expected.update({name: hashlib.sha256((out / name).read_bytes()).hexdigest() for name in pins})
            self.assertEqual(manifest['files'], expected)

    def test_pinned_routes_carry_their_certificate(self):
        # Mario Kart 8 Deluxe's NEX server presents a self-signed certificate: its routes accept exactly that one, and its address too
        mk8 = '0100152000022000'; value = n.contract(REPO); rows = [line.split('\t') for line in n.rules(value, mk8).splitlines()[1:]]
        pins = [row for row in rows if row[0].startswith('pinned-')]
        self.assertEqual({row[0] for row in pins}, {'pinned-exact', 'pinned-address'})
        for row in pins:
            self.assertEqual(row[4], row[5] + '.der')
            self.assertEqual(hashlib.sha256((REPO / n.PINS / row[4]).read_bytes()).hexdigest(), row[5])
            self.assertEqual(row[3], row[1] if row[0] == 'pinned-exact' else 'g2b309e01-lp1.s.n.srv.nintendo.net')
        with tempfile.TemporaryDirectory() as folder:
            ca = b'synthetic public CA bytes'; value['provider']['caSHA256'] = hashlib.sha256(ca).hexdigest()
            with patch.object(n, 'contract', return_value=value):
                out = n.prepare(REPO, mk8, Path(folder) / 'profile', ca=ca)
            self.assertTrue((out / (pins[0][5] + '.der')).is_file())
        broken = n.contract(REPO); broken['base'] = [dict(broken['base'][-1], tls=False)]
        with self.assertRaises(ValueError): n.rules(broken, mk8)


if __name__ == '__main__': unittest.main()
