"""Synthetic MSL for Z-A's cascade rewrite, with no shader data from the game."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1] / 'tools'
sys.path.insert(0, str(TOOLS))
from dmsh_chain import MAC_METAL  # noqa: E402
from dmsh_rewrite import ZA_CASCADE_MSL, za_shadow_cascades  # noqa: E402

HEAD = '''#include <metal_stdlib>
using namespace metal;
struct Support { uint a; uint4 b[8]; float4 c, d; int e; float4 _m5[73]; };
struct Uniforms { float4 _m0[4096]; };
struct Lengths { uint4 _m0[4]; };
struct Args {
    constant Support* support_buffer [[id(0)]];
    constant Uniforms* fp_c3 [[id(1)]];
    constant Uniforms* fp_c6 [[id(2)]];
    constant Lengths* fp_c25 [[id(3)]];
    texture2d_array<float> fp_t_tcb_28 [[id(4)]];
    texture2d_array<float> fp_t_tcb_38 [[id(5)]];
    sampler s [[id(6)]];
};
static int _999(int n, int i, constant Support& s) { return int(float(n) / s._m5[1 + i].x); }
'''
ARGS = 'spvDescriptorSet0'
C3, C6, C25 = (f'(*{ARGS}.fp_c{n})._m0' for n in (3, 6, 25))
DEPTH, IDS = (f'{ARGS}.fp_t_tcb_{n}' for n in (28, 38))


def fixture(*, reversed_products=False, missing_row=False, sample_bias=True, id_height=False):
    lines = []

    def v(t, e):
        name = f'_{len(lines) + 1}'
        lines.append(f'    {t} {name} = {e};')
        return name

    def load(bank, bound, byte):
        word = v('uint', f'uint(int(uint({byte}) >> uint(2)))')
        row = v('uint', f'uint(int(uint(int({word})) >> uint(2)))')
        i = v('int', f'int({row})')
        col = v('int', f'int({word}) & 3')
        ok = v('bool', f'uint({i}) < ({C25}[0].{bound} >> 4u)')
        return v('float', f'select(0.0, {bank}[{ok} ? {i} : 0][{col}], {ok})')

    splits = [v('int', f'int({C3}[133].{k} < coord.x)') for k in 'xyz']
    count = v('int', ' + '.join(splits))
    limit = v('int', '2')
    layer = v('int', f'min({count}, {limit})')
    offset = v('int', f'{layer} << 6')
    matrix = [load(C6, 'w', v('int', f'{offset} + {i}') if i else offset)
              for i in range(0, 56 if missing_row else 64, 8)]
    radius = load(C3, 'x', v('int', f'{count} + 2452'))
    bias = v('float', f'float({layer})' if sample_bias else f'float({limit})')
    extent_slot = v('int', '0')
    dims = []
    for axis in 'xy':
        t = IDS if axis == 'y' and id_height else DEPTH
        q = v('int', f'int3({t}.get_width(), {t}.get_height(), {t}.get_array_size()).{axis}')
        q = v('int', q)
        q = v('int', f'_999({q}, {extent_slot}, (*{ARGS}.support_buffer))')
        q = v('float', f'float(uint({q}))')
        rec = v('float', f'1.0 / {q}')
        operands = (rec, radius) if reversed_products else (radius, rec)
        dims.append(v('float', ' * '.join(operands)))
    # Keep samples and object-ID logic in place; their three layers remain the game's decision.
    color = ' '.join(f'    sum += {DEPTH}.sample({ARGS}.s, coord.xy + float2({dims[0]}, {dims[1]}) * {i}.0, uint({layer}), bias({bias})).x;\n'
                     for i in range(16))
    return HEAD + f'fragment float f(constant Args& {ARGS} [[buffer(0)]], float4 coord [[position]])\n{{\n' + '\n'.join(lines) + (
        '\n    float sum = 0.0;\n' + color + f'    return sum + {IDS}.read(uint2(0u), uint({layer}), 0u).x + ' + ' + '.join(matrix) + ';\n}\n')


class ShadowCascades(unittest.TestCase):
    def test_patches_only_the_two_pcf_products(self):
        for flipped in (False, True):
            src = fixture(reversed_products=flipped)
            out = za_shadow_cascades(src)
            self.assertEqual(out.count(' * dm_za_scale.'), 2)
            self.assertIn(' * dm_za_scale.x;', out)
            self.assertIn(' * dm_za_scale.y;', out)
            self.assertEqual(re.sub(r'^    float2 dm_za_scale = .*;\n', '', out, flags=re.M)
                             .replace('\n' + ZA_CASCADE_MSL, '').replace(' * dm_za_scale.x', '').replace(' * dm_za_scale.y', ''), src)

    def test_refuses_incomplete_and_wrong_inputs(self):
        src = fixture()
        for bad in (fixture(missing_row=True), fixture(id_height=True), fixture(sample_bias=False),
                    src.replace(' + 2452;', ' + 2332;'), src.replace(f'{C3}[133].z', f'{C3}[134].z'),
                    src.replace(' >> 4u);', ' >> 3u);'), src.replace(f'{IDS}.read(', f'{DEPTH}.read(')):
            self.assertEqual(za_shadow_cascades(bad), bad)
        # A changed definition is not SSA and cannot prove the PCF footprint.
        radius = re.search(r'float (_\d+) = select\(0\.0, \(\*spvDescriptorSet0\.fp_c3\)', src)
        assert radius
        end = src.index('\n', radius.end())
        bad = src[:end] + f'\n    {radius[1]} = 0.0;' + src[end:]
        self.assertEqual(za_shadow_cascades(bad), bad)

    @unittest.skipUnless(os.environ.get('DMSH_TEST_METAL') == '1', 'set DMSH_TEST_METAL=1 to compile the rewritten fragment')
    def test_metal_compiles(self):
        with tempfile.TemporaryDirectory() as d:
            source, air = Path(d, 'cascade.metal'), Path(d, 'cascade.air')
            source.write_text(za_shadow_cascades(fixture()))
            r = subprocess.run(MAC_METAL + [str(source), '-o', str(air)], capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)


if __name__ == '__main__':
    if sys.argv[1:2] == ['--fixture']:
        Path(sys.argv[2]).write_text(HEAD + ZA_CASCADE_MSL + '''
kernel void check(constant float4* m [[buffer(0)]], constant Support& s [[buffer(1)]],
                  device float2* out [[buffer(2)]], uint i [[thread_position_in_grid]])
{
    out[i] = dm_za_cascade_scale(m, i == 4 ? 7u : 12u, i == 4 || i == 5 ? 1u : i, s._m5[0].y, i == 5 ? 4u : 3u);
}
''')
    else:
        unittest.main()
