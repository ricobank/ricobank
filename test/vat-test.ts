import { expect as want } from 'chai'

import * as hh from 'hardhat'
import { ethers, artifacts, network } from 'hardhat'

import { send, wad, ray, rad, N, U256_MAX, warp } from 'minihat'

import { snapshot, revert, b32 } from './helpers'

const debug = require('debug')('rico:test')

const i0 = Buffer.alloc(32) // ilk 0 id

describe('Vat', () => {
  let ali, bob, cat
  let ALI, BOB, CAT
  let vat; let vat_type
  let joy, gem; let gem_type
  let vault; let vault_type
  before(async () => {
    [ali, bob, cat] = await ethers.getSigners();
    [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address)
    vat_type = await ethers.getContractFactory('./src/vat.sol:Vat', ali)
    const gem_artifacts = require('../lib/gemfab/artifacts/sol/gem.sol/Gem.json')
    gem_type = ethers.ContractFactory.fromSolidity(gem_artifacts, ali)
    vault_type = await ethers.getContractFactory('./src/vault.sol:Vault', ali)

    vat = await vat_type.deploy()
    joy = await gem_type.deploy('joy', 'JOY')
    gem = await gem_type.deploy('gem', 'GEM')
    vault = await vault_type.deploy()

    await send(vat.rely, vault.address)
    await send(joy.rely, vault.address)
    await send(gem.rely, vault.address)

    await send(joy.approve, vault.address, U256_MAX)
    await send(gem.approve, vault.address, U256_MAX)
    await send(joy.mint, ALI, wad(1000))
    await send(gem.mint, ALI, wad(1000))

    await send(vault.file_gem, i0, gem.address)
    await send(vault.file_vat, vat.address, true)
    await send(vault.file_joy, joy.address, true)
    await send(vault.gem_join, vat.address, i0, ALI, wad(1000))

    await send(vat.init, i0)
    await send(vat.file, b32('Line'), rad(1000))
    await send(vat.filk, i0, b32('line'), rad(1000))

    await send(vat.plot, i0, ray(1).toString())

    await snapshot(hh);
  })
  beforeEach(async () => {
    await revert(hh);
  })

  it('init conditions', async () => {
    const isWarded = await vat.wards(ALI)
    want(isWarded).true
  })

  it('gem join', async () => {
    const gembal = await vat.gem(Buffer.alloc(32), ALI)
    want(gembal.eq(wad(1000))).true
    const bal = await gem.balanceOf(ALI)
    want(bal.eq(wad(0))).true
  })

  it('frob', async () => {
    // lock 6 wads
    await send(vat.frob, i0, ALI, ALI, ALI, wad(6), 0)

    const [ink, art] = await vat.urns(i0, ALI)
    want(ink.eq(wad(6))).true
    const gembal = await vat.gem(i0, ALI)
    want(gembal.eq(wad(994))).true

    const _6 = N(0).sub(wad(6))
    await send(vat.frob, i0, ALI, ALI, ALI, _6, 0)

    const [ink2, art2] = await vat.urns(i0, ALI)
    want((await vat.gem(i0, ALI)).eq(wad(1000))).true
  })

  it('drip', async () => {
    const _2pc = ray(1).add(ray(1).div(50))

    const [, rateparam] = await vat.ilks(i0)

    const t0 = (await vat.time()).toNumber()

    await warp(hh, t0 + 1);

    await send(vat.filk, i0, b32('duty'), _2pc)

    const t1 = (await vat.time()).toNumber()

    const [, rateparam2] = await vat.ilks(i0)

    await warp(hh, t0 + 2);

    await send(vat.frob, i0, ALI, ALI, ALI, wad(100), wad(50))

    const debt1 = await vat.callStatic.owed(i0, ALI)

    await warp(hh, t0 + 3);

    const debt2 = await vat.callStatic.owed(i0, ALI)
  })

  it('feed plot safe', async () => {
    const safe0 = await vat.callStatic.safe(i0, ALI)
    want(safe0).true

    await send(vat.frob, i0, ALI, ALI, ALI, wad(100), wad(50))

    const safe1 = await vat.callStatic.safe(i0, ALI)
    want(safe1).true

    const [ink, art] = await vat.urns(i0, ALI)
    want(ink.eq(wad(100))).true
    want(art.eq(wad(50))).true

    const [,,mark0] = await vat.ilks(i0)
    want(mark0.eq(ray(1))).true

    await send(vat.plot, i0, ray(1))

    const [,,mark0] = await vat.ilks(i0)
    want(mark0.eq(ray(1))).true

    const safe2 = await vat.callStatic.safe(i0, ALI)
    want(safe2).true

    await send(vat.plot, i0, ray(1).div(5))

    const safe3 = await vat.callStatic.safe(i0, ALI)
    want(safe3).false
  })
})
