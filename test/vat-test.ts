import _debug from 'debug'
const debug = _debug('rico:test');
import { expect as want } from 'chai'

import { ethers, artifacts, network } from 'hardhat'

import { send, wad, ray, rad, N } from './helpers';


const UMAX = N(2).pow(N(256)).sub(N(1));

const YEAR = ((365 * 24) + 6) * 3600;

let i0 = Buffer.alloc(32); // ilk 0 id

describe('Vat', () => {
  let ali, bob, cat;
  let ALI, BOB, CAT;
  let vat; let vat_type;
  let dai, gem; let gem_type;
  let daijoin; let daijoin_type;
  let gemjoin; let gemjoin_type;
  before(async() => {
    [ali, bob, cat] = await ethers.getSigners();
    [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address);
    vat_type = await ethers.getContractFactory('./src/vat.sol:Vat', ali);
    gem_type = await ethers.getContractFactory('./src/gem.sol:Gem', ali);
    daijoin_type = await ethers.getContractFactory('./src/join.sol:DaiJoin', ali);
    gemjoin_type = await ethers.getContractFactory('./src/join.sol:GemJoin', ali);
  });
  beforeEach(async() => {
    vat = await vat_type.deploy();
    dai = await gem_type.deploy('dai', 'DAI');
    gem = await gem_type.deploy('gem', 'GEM');
    daijoin = await daijoin_type.deploy(vat.address, dai.address);
    gemjoin = await gemjoin_type.deploy(vat.address, Buffer.alloc(32), gem.address);

    await send(vat.rely, daijoin.address);
    await send(vat.rely, gemjoin.address);
    await send(dai.rely, daijoin.address);
    await send(gem.rely, gemjoin.address);

    await send(dai.approve, daijoin.address, UMAX);
    await send(gem.approve, gemjoin.address, UMAX);
    await send(dai.mint, ALI, wad(1000).toString());
    await send(gem.mint, ALI, wad(1000).toString());

    await send(vat.init, i0);
    await send(vat.file_Line, rad(1000).toString());
    await send(vat.file_line, i0, rad(1000).toString());

    await send(vat.plot, i0, ray(1).toString());

    await send(gemjoin.join, ALI, wad(1000).toString());
  });

  it('init conditions', async()=>{
    const isWarded = await vat.wards(ALI);
    want(isWarded).true
  });

  it('gem join', async() => {
    const gembal = await vat.gem(Buffer.alloc(32), ALI);
    want(gembal.eq(wad(1000))).true
    const bal = await gem.balanceOf(ALI);
    want(bal.eq(wad(0))).true;
  });

  it('frob', async() => {
    // lock 6 wads
    await send(vat.frob, i0, ALI, ALI, ALI, wad(6), 0);

    const [ink, art] = await vat.urns(i0, ALI);
    want(ink.eq(wad(6))).true
    const gembal = await vat.gem(i0, ALI);
    want(gembal.eq(wad(994))).true

    const _6 = N(0).sub(wad(6));
    await send(vat.frob, i0, ALI, ALI, ALI, _6, 0);

    const [ink2, art2] = await vat.urns(i0, ALI);
    want((await vat.gem(i0, ALI)).eq(wad(1000))).true
  });

  it('drip', async () => {
    const _2pc = ray(1).add(ray(1).div(50));

    const [_, rateparam] = await vat.ilks(i0);

    const t0 = (await vat.time()).toNumber();

    await network.provider.request({ method: 'evm_setNextBlockTimestamp', params: [t0 + 1] })

    const tx_file_duty = await vat.file_duty(i0, _2pc);
    await tx_file_duty.wait();

    const t1 = (await vat.time()).toNumber();

    const [_, rateparam2] = await vat.ilks(i0);

    await network.provider.request({ method: 'evm_setNextBlockTimestamp', params: [t0 + 2] })

    const tx_frob1 = await vat.frob(i0, ALI, ALI, ALI, wad(100), wad(50));
    await tx_frob1.wait();

    const debt1 = await vat.callStatic.wowed(i0, ALI);

    await network.provider.request({ method: 'evm_setNextBlockTimestamp', params: [t0 + 3] })

    const debt2 = await vat.callStatic.wowed(i0, ALI);

  });

  it('feed plot safe', async () => {
    const safe0 = await vat.callStatic.safe(i0, ALI);
    want(safe0).true

    const tx_frob1 = await vat.frob(i0, ALI, ALI, ALI, wad(100), wad(50));
    await tx_frob1.wait();

    const safe1 = await vat.callStatic.safe(i0, ALI);
    want(safe1).true

    const [ink, art] = await vat.urns(i0, ALI);
    want(ink.eq(wad(100))).true
    want(art.eq(wad(50))).true

    const [,,mark0] = await vat.ilks(i0);
    want(mark0.eq(ray(1))).true

    const tx_plot1 = await vat.plot(i0, ray(1));
    await tx_plot1.wait();

    const [,,mark0] = await vat.ilks(i0);
    want(mark0.eq(ray(1))).true

    const safe2 = await vat.callStatic.safe(i0, ALI);
    want(safe2).true

    const tx_plot2 = await vat.plot(i0, ray(1).div(5))
    await tx_plot2.wait();

    const safe3 = await vat.callStatic.safe(i0, ALI);
    want(safe3).false

  })

});
