import _debug from 'debug'
const debug = _debug('rico:test');
import { expect as want } from 'chai'

import { ethers, artifacts, network } from 'hardhat'
const { hexZeroPad } = ethers.utils

import { send, N, wad, ray, rad, BANKYEAR } from './helpers'

const bn2b32 = (bn) => hexZeroPad(bn.toHexString(), 32);

const i0 = Buffer.alloc(32); // ilk 0 id
const ADDRZERO = "0x" + "00".repeat(20)
const TAG = Buffer.from("feed".repeat(16), 'hex');

const wait = async (t) => await network.provider.request({
  method: 'evm_increaseTime',
  params: [t]
});

const warp = async (t) => await network.provider.request({
  method: 'evm_setNextBlockTimestamp',
  params: [t]
});

const mine = async (t) => {
  if (t !== undefined) {
    await wait(t);
  }
  await network.provider.request({
    method: 'evm_mine'
  });
}

describe('Vox', ()=> {
  let ali, bob, cat;
  let ALI, BOB, CAT;
  let vat; let vat_type;
  let vox; let vox_type;

  const fbpack = require('../lib/feedbase')
  let fb_deployer;
  let fb;


  before(async() => {
    [ali, bob, cat] = await ethers.getSigners();
    [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address);
    vat_type = await ethers.getContractFactory('./src/vat.sol:Vat', ali);
    vox_type = await ethers.getContractFactory('./src/vox.sol:Vox', ali);

    await fbpack.init();
    const fb_artifacts = fbpack.dapp._raw.types.Feedbase.artifacts;
    fb_deployer = ethers.ContractFactory.fromSolidity(fb_artifacts, ali);
  });
  beforeEach(async() => {
    vat = await vat_type.deploy();
    vox = await vox_type.deploy();
    fb = await fb_deployer.deploy();

    await send(vat.rely, vox.address);

    await send(vox.file_feedbase, fb.address);
    await send(vox.file_vat, vat.address);
    await send(vox.file_feed, ALI, TAG);

    await send(vat.spar, wad(7));
  });

  it('sway', async() => {
    await send(vat.spar, wad(7));

    await warp(10**10);
    await mine();

    const t0 = await vat.time();
    want(t0.toNumber()).equal(10**10);

    await wait(10);
    await mine();

    const t1 = await vat.time();
    want(t1.toNumber()).equal(10**10 + 10);

    const par0 = await vat.par(); // jammed to 7
    want(par0.eq(wad(7))).true

    await send(fb.push, TAG, bn2b32(wad(7)), t1.toNumber() + 1000, ADDRZERO);

    await send(vat.prod);

    const par1 = await vat.par(); // still at 7 because way == RAY
    want(par1.eq(wad(7))).true

    const t2 = await vat.time();

    await send(vat.sway, ray(2));// doubles every second (!)
    await send(vat.prod);

    await wait(1);
    await mine();

    const par2 = await vat.par();
    want(par2.eq(wad(14))).true

  });

  it('ricolike vox', async() => {
    const t0 = 10**11;
    await warp(t0);
    await mine();
    const t10 = t0 + 10;
    await warp(t10);
    await mine();
    const t10_ = await vat.time();
    want(t10_.toNumber()).equals(t10);

    await send(vat.spar, wad(1.24));
    await send(vox.file_how, ray(1.00000001));

    await send(fb.push, TAG, bn2b32(wad(1.25)), 10**12, ADDRZERO);
    await send(vox.poke);

    await warp(t0 + 3600);
    await mine();

    await send(vox.poke);
    const par2 = await vat.par();

    await warp(t0 + 2*3600);
    await mine();

    await send(vox.poke);
    const par3 = await vat.par();

  });

});
