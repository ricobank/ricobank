import { expect as want } from 'chai'

import * as hh from 'hardhat'
import { ethers } from 'hardhat'

import { b32, snapshot, revert } from './helpers'
import { wait, mine, wad, ray, rad, apy, send, BANKYEAR, U256_MAX } from 'minihat'
const debug = require('debug')('rico:test')

const i0 = Buffer.alloc(32) // ilk 0 id

describe('vow / liq liquidation lifecycle', () => {
  let ali, bob, cat
  let ALI, BOB, CAT
  let RICO, RISK, WETH; let gem_type
  let vat; let vat_type
  let vault; let vault_type
  let vow; let vow_type
  let flower; let flower_type;
  before(async () => {
    [ali, bob, cat] = await ethers.getSigners();
    [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address)
    const gem_artifacts = require('../lib/gemfab/artifacts/sol/gem.sol/Gem.json')
    gem_type = ethers.ContractFactory.fromSolidity(gem_artifacts, ali)
    vat_type = await ethers.getContractFactory('Vat', ali)
    vow_type = await ethers.getContractFactory('Vow', ali)
    vault_type = await ethers.getContractFactory('Vault', ali)
    flower_type = await ethers.getContractFactory('RicoFlowerV1', ali)

    vat = await vat_type.deploy()
    vault = await vault_type.deploy()
    vow = await vow_type.deploy()
    flower = await flower_type.deploy();
    RICO = await gem_type.deploy('Rico', 'RICO')
    RISK = await gem_type.deploy('Rico Riskshare', 'RISK')
    WETH = await gem_type.deploy('Wrapped Ether', 'WETH')

    await send(vat.hope, vault.address)
    await send(vat.rely, vault.address)
    await send(vat.rely, vow.address)
    await send(RICO.rely, vault.address)
    await send(WETH.rely, vault.address)

    await send(RICO.approve, vault.address, U256_MAX)
    await send(WETH.approve, vault.address, U256_MAX)
    // await send(RICO.mint, ALI, wad(1000));   draw from cdp
    await send(WETH.mint, ALI, wad(1000))

    await send(vault.file_gem, i0, WETH.address)
    await send(vault.file_vat, vat.address, true)
    await send(vault.file_joy, RICO.address, true)
    await send(vault.gem_join, vat.address, i0, ALI, wad(1000))

    await send(vat.init, i0)
    await send(vat.file, b32('ceil'), rad(1000))
    await send(vat.filk, i0, b32('line'), rad(1000))
    await send(vat.filk, i0, b32('liqr'), ray(1))
    await send(vat.filk, i0, b32('chop'), ray(1.1))

    await send(vow.file_vat, vat.address)
    await send(vow.file_vault, vault.address)
    await send(vow.file_flipper, i0, flower.address)


    await send(vat.plot, i0, ray(1))
    await send(vat.filk, i0, b32('duty'), apy(1.05))
    await send(vat.lock, i0, wad(100))
    await send(vat.draw, i0, wad(99))

    await send(vault.joy_exit, vat.address, RICO.address, ALI, wad(99))
    const bal = await RICO.balanceOf(ALI)
    want(bal.toString()).equals(wad(99).toString())
    const safe1 = await vat.callStatic.safe(i0, ALI)
    want(safe1).true

    await snapshot(hh)
  })
  beforeEach(async () => {
    await revert(hh)
  })

  it('vow 1yr not safe bail', async () => {

    await mine(hh, BANKYEAR)

    const safe2 = await vat.callStatic.safe(i0, ALI)
    want(safe2).false

    const sin0 = await vat.sin(vow.address)
    const gembal0 = await WETH.balanceOf(flower.address)
    want(sin0.eq(0)).true
    want(gembal0.eq(0)).true

    await send(vow.bail, i0, ALI)

    const sin1 = await vat.sin(vow.address)
    const gembal1 = await WETH.balanceOf(flower.address)
    want(sin1.gt(0)).true
    want(gembal1.gt(0)).true
  })

  it('vow 1yr drip flap', async () => {
    await mine(hh, BANKYEAR)

    await send(vat.drip, i0);
  })
})
