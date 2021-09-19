import _debug from 'debug'
const debug = _debug('rico:test');
import { expect as want } from 'chai'

import { ethers, artifacts, network } from 'hardhat'

let bn = (n) => ethers.BigNumber.from(n)

const UMAX = bn(2).pow(bn(256)).sub(bn(1));

const YEAR = ((365 * 24) + 6) * 3600;

let wad = (n: number) => bn(n).mul(bn(10).pow(bn(18)))
let ray = (n: number) => bn(n).mul(bn(10).pow(bn(27)))
let rad = (n: number) => bn(n).mul(bn(10).pow(bn(45)))

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

    // vat.rely(daijoin)
    const tx_rely1 = await vat.rely(daijoin.address);
    await tx_rely1.wait();

    // vat.rely(gemjoin)
    const tx_rely2 = await vat.rely(gemjoin.address);
    await tx_rely2.wait();

    // dai.rely(daijoin)
    const tx_rely3 = await vat.rely(gemjoin.address);
    await tx_rely3.wait();

    // gem.rely(gemjoin)
    const tx_rely4 = await gem.rely(gemjoin.address);
    await tx_rely4.wait();

    const tx_approve_dai = await dai.approve(daijoin.address, UMAX);
    await tx_approve_dai.wait();

    const tx_approve_gem = await gem.approve(gemjoin.address, UMAX);
    await tx_approve_gem.wait();

    const tx_mint_dai = await dai.mint(ALI, wad(1000).toString());
    await tx_mint_dai.wait();

    const tx_mint_gem = await gem.mint(ALI, wad(1000).toString());
    await tx_mint_gem.wait();

    const tx_init = await vat.init(Buffer.alloc(32));
    await tx_init.wait();

    const tx_file_Line = await vat.file_Line(rad(1000).toString());
    await tx_file_Line.wait();

    const tx_file_line = await vat.file_line(i0, rad(1000).toString());
    await tx_file_line.wait();

    const tx_plot = await vat.plot(i0, ray(1).toString());
    await tx_plot.wait();

    const tx_join = await gemjoin.join(ALI, wad(1000).toString());
    await tx_join.wait();
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
    const tx_frob1 = await vat.frob(i0, ALI, ALI, ALI, wad(6), 0);
    await tx_frob1.wait();

    const [ink, art] = await vat.urns(i0, ALI);
    want(ink.eq(wad(6))).true
    const gembal = await vat.gem(i0, ALI);
    want(gembal.eq(wad(994))).true

    const _6 = bn(0).sub(wad(6));
    const tx_frob2 = await vat.frob(i0, ALI, ALI, ALI, bn(0).sub(wad(6)), 0)
    await tx_frob2.wait();

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
