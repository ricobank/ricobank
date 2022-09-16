import { expect as want } from 'chai'

import * as hh from 'hardhat'
// @ts-ignore
import { ethers } from 'hardhat'
const { hexZeroPad } = ethers.utils

import { fail, send, wad, ray, rad, N, U256_MAX, warp, snapshot, revert } from 'minihat'
import { constants } from 'ethers'

import { b32 } from './helpers'

const dpack = require('@etherpacks/dpack')
const debug = require('debug')('rico:test')

const i0 = Buffer.alloc(32) // ilk 0 id
const wtag = b32('WETHUSD')
const bn2b32 = (bn) => hexZeroPad(bn.toHexString(), 32)
const gettime = async () => {
    const blocknum = await ethers.provider.getBlockNumber()
    return (await ethers.provider.getBlock(blocknum)).timestamp
}

describe('Vat', () => {
  let ali, bob, cat, dan
  let ALI, BOB, CAT, DAN
  let vat; let vat_type
  let gem_type
  let dock, flower, vow
  let fb, t1
  let RICO, RISK, WETH
  before(async () => {
    [ali, bob, cat, dan] = await ethers.getSigners();
    [ALI, BOB, CAT, DAN] = [ali, bob, cat, dan].map(signer => signer.address)
    vat_type = await ethers.getContractFactory('MockVat', ali)
    const gem_artifacts = require('../lib/gemfab/artifacts/src/gem.sol/Gem.json')
    gem_type = ethers.ContractFactory.fromSolidity(gem_artifacts, ali)
    const pack = await hh.run('deploy-ricobank', { mock: 'true' })
    const dapp = await dpack.load(pack, ethers, ali)
    t1 = await gettime()

    vat = await vat_type.deploy()
    flower = dapp.flow
    dock = dapp.dock
    vow = dapp.vow
    RICO = dapp.rico
    RISK = dapp.risk
    WETH = dapp.weth
    fb = dapp.feedbase

    await send(vat.ward, dock.address, true)
    await send(WETH.approve, dock.address, U256_MAX)

    await send(dock.bind_gem, vat.address, i0, WETH.address)
    await send(dock.bind_joy, vat.address, RICO.address, true)

    await send(vat.init, i0, WETH.address, ALI, wtag)
    await send(vat.file, b32('ceil'), rad(1000))
    await send(vat.filk, i0, b32('line'), rad(1000))
    await send(vat.link, b32('feeds'), fb.address);

    await send(fb.push, wtag, bn2b32(ray(1)), t1 + 1000)
    await send(WETH.deposit, { value: ethers.utils.parseEther('1000.0') })
    await send(dock.join_gem, vat.address, i0, ALI, wad(1000))
    await send(RICO.mint, ALI, wad(1000))

    await snapshot(hh)
  })
  beforeEach(async () => await revert(hh))

  it('init conditions', async () => {
    const isWarded = await vat.wards(ALI)
    want(isWarded).true
  })

  it('gem join', async () => {
    const gembal = await vat.gem(i0, ALI)
    want(gembal.eq(wad(1000))).true
    const bal = await WETH.balanceOf(ALI)
    want(bal.eq(wad(0))).true
  })

  it('frob', async () => {
    // lock 6 wads
    await send(vat.frob, i0, ALI, wad(6), 0)

    const [ink, art] = await vat.urns(i0, ALI)
    want(ink.eq(wad(6))).true
    const gembal = await vat.gem(i0, ALI)
    want(gembal.eq(wad(994))).true

    const _6 = N(0).sub(wad(6))
    await send(vat.frob, i0, ALI, _6, 0)

    want((await vat.gem(i0, ALI)).eq(wad(1000))).true
  })

  it('rejects unsafe frob', async () => {
    const [ink, art] = await vat.urns(i0, ALI)
    want(ink.toNumber()).to.eql(0)
    want(art.toNumber()).to.eql(0)
    await fail('Vat/not-safe', vat.frob, i0, ALI, 0, wad(1))
  })

  it('drip', async () => {
    const _2pc = ray(1).add(ray(1).div(50))

    const [, rateparam] = await vat.ilks(i0)

    const gettime = async () => {
      const blocknum = await ethers.provider.getBlockNumber()
      return (await ethers.provider.getBlock(blocknum)).timestamp
    }

    const t0 = await gettime()

    await warp(hh, t0 + 1);

    await send(vat.filk, i0, b32('duty'), _2pc)

    const t1 = await gettime()

    const [, rateparam2] = await vat.ilks(i0)

    await warp(hh, t0 + 2);

    await send(vat.frob, i0, ALI, wad(100), wad(50))

    const owed = async () => {
      await send(vat.drip, i0)
      let ilk = await vat.ilks(i0)
      let urn = await vat.urns(i0, ALI)
      return ilk.rack.mul(urn.art)
    }

    const debt1 = await owed()

    await warp(hh, t0 + 4);

    const debt2 = await owed()
    debug(`debt1=${debt1} debt2=${debt2}`)
  })

  it('feed plot safe', async () => {
    const safe0 = await vat.callStatic.safe(i0, ALI)
    want(safe0).eq(2)

    await send(vat.frob, i0, ALI, wad(100), wad(50))

    const safe1 = await vat.callStatic.safe(i0, ALI)
    want(safe1).eq(2)

    const [ink, art] = await vat.urns(i0, ALI)
    want(ink.eq(wad(100))).true
    want(art.eq(wad(50))).true

    await send(fb.push, wtag, bn2b32(ray(1)), t1 + 1000)

    const safe2 = await vat.callStatic.safe(i0, ALI)
    want(safe2).eq(2)

    await send(fb.push, wtag, bn2b32(ray(0.2)), t1 + 1000)

    const safe3 = await vat.callStatic.safe(i0, ALI)
    want(safe3).eq(0)
  })
})
