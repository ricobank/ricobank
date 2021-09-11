import _debug from 'debug'
const debug = _debug('rico:test');
import { expect as want } from 'chai'

import { ethers, artifacts, network } from 'hardhat'

import { BN } from 'bn.js'

const UMAX = (new BN(2)).pow(new BN(256)).sub(new BN(1));

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

    const tx_init = await vat.init(Buffer.alloc(32));
    await tx_init.wait();

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

    const tx_approve_dai = await dai.approve(daijoin.address, '0x' + UMAX.toString('hex'));
    await tx_approve_dai.wait();

    const tx_approve_gem = await gem.approve(gemjoin.address, '0x' + UMAX.toString('hex'));
    await tx_approve_gem.wait();

    const tx_mint_dai = await dai.mint(ALI, 1000);
    await tx_mint_dai.wait();

    const tx_mint_gem = await gem.mint(ALI, 1000);
    await tx_mint_gem.wait();

  });

  it('init conditions', async()=>{
    const isWarded = await vat.wards(ALI);
    want(isWarded.eq(1)).true
    const initDai = await dai.balanceOf(ALI);
    want(initDai.eq(1000)).true
  });

  it('gem join', async() => {
    const tx_join = await gemjoin.join(ALI, 500);
    await tx_join.wait();

    const gembal = await vat.gem(Buffer.alloc(32), ALI);
    want(gembal.eq(500)).true
  });

});
