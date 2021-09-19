import _debug from 'debug'
const debug = _debug('rico:test');
import { expect as want } from 'chai'

import { ethers, artifacts, network } from 'hardhat'

const fbpack = require('../lib/feedbase')
let fb;

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

describe('mark vat via marker', () => {
  let ali, bob, cat;
  let ALI, BOB, CAT;
  let vat; let vat_type;
  let marker; let marker_type;
  let fb_deployer;
  before(async()=>{
    await fbpack.init();
    [ali, bob, cat] = await ethers.getSigners();
    [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address);
    vat_type = await ethers.getContractFactory('./src/vat.sol:Vat', ali);
    marker_type = await ethers.getContractFactory('./src/mark.sol:Marker', ali);
    //await fbpack.dapp.useSigner(ali);
    //await fbpack.dapp.useDefaultProvider();
    const artifacts = fbpack.dapp._raw.types.Feedbase.artifacts;
    fb_deployer = ethers.ContractFactory.fromSolidity(artifacts, ali);
  })
  beforeEach(async() => {
    vat = await vat_type.deploy();
    marker = await marker_type.deploy();
    fb = await fb_deployer.deploy();
    //fb = await fbpack.dapp.types.Feedbase.deploy();

    const tx_rely1 = await vat.rely(marker.address);
    await tx_rely1.wait();

    const tx_file_fb = await marker.file_fb(fb.address);
    await tx_file_fb.wait()
    const tx_file_vat = await marker.file_vat(vat.address);
    await tx_file_vat.wait()

    const tx_wire = await marker.wire(i0, ALI, TAG);
    await tx_wire.wait();

  })

  it('mark', async () => {
    const p = Buffer.from(wad(1200).toHexString().slice(2).padStart(64, '0'), 'hex');
    const tx_push = await fb.push(TAG, p, 10**10, ADDRZERO);
    await tx_push.wait();

    const tx_poke = await marker.poke(i0);
    await tx_poke.wait();

    const [,,mark0] = await vat.ilks(i0);
    want(mark0.eq(ray(1200))).true; // upcast to ray by marker

  })

});


