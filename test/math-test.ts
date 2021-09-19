import _debug from 'debug'
const debug = _debug('rico:test');
import { expect as want } from 'chai'

import { ethers, artifacts } from 'hardhat'

describe('math.sol', ()=>{
  let ali, bob, cat;
  let ALI, BOB, CAT;
  let BLN, WAD, RAY;
  let stub;
  before(async() => {
    [ali, bob, cat] = await ethers.getSigners();
    [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address);
  });
  beforeEach(async() => {
    const stub_type = await ethers.getContractFactory('./src/mixin/math_stub.sol:MathStub', ali);
    stub = await stub_type.deploy();
    BLN = await stub._BLN();
    WAD = await stub._WAD();
    RAY = await stub._RAY();
  });

  it('add', async()=>{
    const z = await stub._add(1, 2);
    want(z.eq(3)).true
  });

  it('rpow', async()=>{
    const a = await stub._rpow(RAY, 1);
    want(a.eq(RAY)).true

    const b = await stub._rpow(RAY, 0);
    want(b.eq(RAY)).true;

    const c = await stub._rpow(RAY.mul(2), 2);
    want(c.eq(RAY.mul(4))).true
  });

  it('grow', async() => {
    const a = await stub._grow(WAD, RAY, 1);
    want(a.eq(WAD)).true

    const b = await stub._grow(WAD, RAY, 0);
    want(b.eq(WAD)).true

    const c = await stub._grow(WAD.mul(2), RAY.mul(2), 1);
    want(c.eq(WAD.mul(4))).true

    const d = await stub._grow(WAD.mul(2), RAY.mul(2), 2);
    want(d.eq(WAD.mul(8))).true

    const e = await stub._grow(RAY.div(BLN), RAY, 5);

  });

});
