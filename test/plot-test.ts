import _debug from 'debug'
const debug = _debug('rico:test');
import { expect as want } from 'chai'

import { ethers, artifacts, network } from 'hardhat'

const bn = (n) => ethers.BigNumber.from(n)
const UMAX = bn(2).pow(bn(256)).sub(bn(1));
const YEAR = ((365 * 24) + 6) * 3600;
const wad = (n: number) => bn(n).mul(bn(10).pow(bn(18)))
const ray = (n: number) => bn(n).mul(bn(10).pow(bn(27)))
const rad = (n: number) => bn(n).mul(bn(10).pow(bn(45)))
const ZERO = Buffer.alloc(32);
const ADDRZERO = "0x" + "00".repeat(20)
const i0 = ZERO; // ilk 0 id

const TAG = Buffer.from("feed".repeat(16), 'hex');

describe('plot vat ilk mark via plotter', () => {
  let ali, bob, cat;
  let ALI, BOB, CAT;
  let vat; let vat_type;
  let plotter; let plotter_type;
  let fb_deployer; let fb;
  before(async()=>{
    [ali, bob, cat] = await ethers.getSigners();
    [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address);
    vat_type = await ethers.getContractFactory('./src/vat.sol:Vat', ali);
    plotter_type = await ethers.getContractFactory('./src/plot.sol:Plotter', ali);
    const fb_artifacts = require('../lib/feedbase/artifacts/contracts/Feedbase.sol/Feedbase.json')
    fb_deployer = ethers.ContractFactory.fromSolidity(fb_artifacts, ali);
  })
  beforeEach(async() => {
    vat = await vat_type.deploy();
    plotter = await plotter_type.deploy();
    fb = await fb_deployer.deploy();
    //fb = await fbpack.dapp.types.Feedbase.deploy();

    const tx_rely1 = await vat.rely(plotter.address);
    await tx_rely1.wait();

    const tx_file_fb = await plotter.file_fb(fb.address);
    await tx_file_fb.wait()
    const tx_file_vat = await plotter.file_vat(vat.address);
    await tx_file_vat.wait()

    const tx_wire = await plotter.wire(i0, ALI, TAG);
    await tx_wire.wait();

  })

  it('plot mark', async () => {
    const p = Buffer.from(wad(1200).toHexString().slice(2).padStart(64, '0'), 'hex');
    const tx_push = await fb.push(TAG, p, 10**10, ADDRZERO);
    await tx_push.wait();

    const tx_poke = await plotter.poke(i0);
    await tx_poke.wait();

    const [,,mark0] = await vat.ilks(i0);
    want(mark0.eq(ray(1200))).true; // upcast to ray by plotter

  })

});


