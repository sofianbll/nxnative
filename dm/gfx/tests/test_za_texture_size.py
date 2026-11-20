"""Translate real synthetic Maxwell TXQ with a dynamic LOD, then execute its MSL on Metal."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'dm/tools/tests'))
sys.path.insert(0, str(ROOT / 'dm/gfx/tools'))
from test_txq_type import base, mov, shader
import dmsh_chain, dmsh_reflect


@unittest.skipUnless(os.environ.get('DM_TEST_ZA_SIZE'), 'set DM_TEST_ZA_SIZE to the Metal runner')
class TextureSize(unittest.TestCase):
    def test_all_mips(self):
        xlate = os.environ.get('DMSH_TEST_XLATE', str(Path(dmsh_chain.XLATE_DIR) / 'dmsh_xlate'))
        for shape, mask in (('2d', 3), ('2darray', 7), ('3d', 7)):
            with self.subTest(shape=shape), tempfile.TemporaryDirectory(prefix='za-size-') as tmp:
                d = Path(tmp)
                # Thread X = mip. TXQ writes W,H[,layers/depth] to R4.., SUST.D stores them in rows of an R32Uint image.
                tid = base('S2r') | (0x21 << 20) | (7 << 16)
                txq = base('Txq') | (8 << 36) | (mask << 31) | (1 << 22) | (7 << 16) | 4
                stores = []
                for axis in range(mask.bit_count()):
                    stores += [mov(1, axis), base('SustD') | (0x48 << 36) | (3 << 33) | (4 << 20) | (7 << 16) | (4 + axis)]
                code = d / 'query.bin'; code.write_bytes(shader(tid, txq, stores))
                jobs = d / 'jobs.json'
                jobs.write_text(json.dumps([dict(key='query', stage='cs', code=str(code), tex={'0': shape},
                    img={'0': dict(type='2d', fmt='R32Uint')}, local=[16, 1, 1], debug=True)]))
                subprocess.run([xlate, str(jobs), tmp], check=True)
                msl = d / 'query.metal'
                subprocess.run([dmsh_chain.SPIRV_CROSS, *dmsh_chain.CROSS_MSL, str(d / 'query.spv'), '--output', str(msl)], check=True)
                text = msl.read_text()
                def arg(pattern):
                    match = re.search(pattern + r'\s+\w+\s+\[\[id\((\d+)\)\]\]', text)
                    self.assertIsNotNone(match, text)
                    return match[1]
                support = re.search(r'support_buffer\s+\[\[id\((\d+)\)\]\]', text)
                texture = arg(r'texture\w*<float>')
                res = json.loads((d / 'query.res.json').read_text())
                binds = dmsh_reflect.reflect('query', 'cs', text, res)
                binding, = [b for b in binds if b['arg_id'] == int(texture)]
                aid = [support[1] if support else '-1', texture, arg(r'texture2d<uint, access::write>'), str(binding['rs_index'] + 1)]
                air, library = d / 'query.air', d / 'query.metallib'
                subprocess.run([*dmsh_chain.MAC_METAL, str(msl), '-o', str(air)], check=True)
                subprocess.run(['xcrun', '-sdk', 'macosx', 'metallib', str(air), '-o', str(library)], check=True)
                for scale in ('1', '1.5', '2'):
                    subprocess.run([os.environ['DM_TEST_ZA_SIZE'], scale, str(library), shape, *aid], check=True)


if __name__ == '__main__':
    unittest.main()
