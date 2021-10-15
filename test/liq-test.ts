import _debug from 'debug'
const debug = _debug('rico:test');
import { expect as want } from 'chai'

import { ethers } from 'hardhat'

import { send, wait, mine, wad, ray, rad, apy, N, b32, BANKYEAR } from './helpers';

const gempack = require('../lib/gemfab')

const UMAX = N(2).pow(N(256)).sub(N(1));

let i0 = Buffer.alloc(32); // ilk 0 id

describe('liq liquidation cycle', () => {
  let ali, bob, cat;
  let ALI, BOB, CAT;
  let RICO, RISK, WETH; let gem_type;
  let vat; let vat_type;
  let vault; let vault_type;
  let bat; let bat_type;
  let FLIPPER; let VOW;
  before(async() => {
    await gempack.init();
    [ali, bob, cat] = await ethers.getSigners();
    [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address);
    const gem_artifacts = gempack.dapp._raw.types.Gem.artifacts
    gem_type = ethers.ContractFactory.fromSolidity(gem_artifacts, ali);
    vat_type = await ethers.getContractFactory('./src/vat.sol:Vat', ali);
    bat_type = await ethers.getContractFactory('./src/bat.sol:Bat', ali);
    vault_type = await ethers.getContractFactory('./src/vault.sol:Vault', ali);

  });
  beforeEach(async() => {
    vat = await vat_type.deploy();
    vault = await vault_type.deploy();
    bat = await bat_type.deploy();
    RICO = await gem_type.deploy('Rico', 'RICO');
    RISK = await gem_type.deploy('Rico Riskshare', 'RISK');
    WETH = await gem_type.deploy('Wrapped Ether', 'WETH');

    FLIPPER = BOB;
    VOW = CAT;

    await send(vat.hope, vault.address);
    await send(vat.rely, vault.address);
    await send(vat.rely, bat.address);
    await send(RICO.rely, vault.address);
    await send(WETH.rely, vault.address);

    await send(RICO.approve, vault.address, UMAX);
    await send(WETH.approve, vault.address, UMAX);
    //await send(RICO.mint, ALI, wad(1000));   draw from cdp
    await send(WETH.mint, ALI, wad(1000));

    await send(vault.file_gem, i0, WETH.address);
    await send(vault.file_vat, vat.address, true);
    await send(vault.file_joy, RICO.address, true);
    await send(vault.gem_join, vat.address, i0, ALI, wad(1000));

    await send(vat.init, i0);
    await send(vat.file, b32("Line"), rad(1000));
    await send(vat.filk, i0, b32("line"), rad(1000));
    await send(vat.filk, i0, b32("liqr"), ray(1));
    await send(vat.filk, i0, b32("chop"), ray(1.1));

    await send(bat.file_vat, vat.address);
    await send(bat.file_vault, vault.address);
    await send(bat.file_flipper, i0, FLIPPER);
    await send(bat.file_vow, VOW);

  });

  it('init plot filk lock draw safe bite flip flap flop', async()=>{
    await send(vat.plot, i0, ray(1));
    await send(vat.filk, i0, b32("duty"), apy(1.05));
    await send(vat.lock, i0, wad(100));
    await send(vat.draw, i0, wad(99));

    await send(vault.joy_exit, vat.address, RICO.address, ALI, wad(99));
    const bal = await RICO.balanceOf(ALI);
    want(bal.toString()).equals(wad(99).toString());
    console.log("safe 1");
    const safe1 = await vat.callStatic.safe(i0, ALI);
    want(safe1).true;

    await wait(BANKYEAR);
    await mine(BANKYEAR);

    console.log("safe 2");
    const safe2 = await vat.callStatic.safe(i0, ALI);
    want(safe2).false;

    console.log("calling bite...");
    await send(bat.bite, i0, ALI);

    const sin = await vat.sin(VOW);
    debug('vow sin', sin);
    const gembal = await WETH.balanceOf(FLIPPER);
    debug('flipper gembal', gembal);
  });

});
