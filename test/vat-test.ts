import { expect as want } from 'chai'

import * as hh from 'hardhat'
import { ethers } from 'hardhat'

import { fail, send, wad, ray, rad, N, U256_MAX, warp } from 'minihat'

import { snapshot, revert, b32 } from './helpers'

const dpack = require('dpack')
const debug = require('debug')('rico:test')

const i0 = Buffer.alloc(32) // ilk 0 id

describe('Vat', () => {
  let ali, bob, cat
  let ALI, BOB, CAT
  let vat
  let RICO, WETH
  let join
  let port
  before(async () => {
    [ali, bob, cat] = await ethers.getSigners();
    [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address)
    const pack = await hh.run('deploy-ricobank', { mock: 'true' })
    const dapp = await dpack.Dapp.loadFromPack(pack, ali, ethers)

    join = dapp.objects.join
    port = dapp.objects.port
    vat = dapp.objects.vat
    RICO = dapp.objects.rico
    WETH = dapp.objects.weth9

    await send(vat.ward, join.address, true)
    await send(WETH.approve, join.address, U256_MAX)
    await send(RICO.mint, ALI, wad(1000))
    await send(WETH.deposit, { value: ethers.utils.parseEther('1000.0') })

    await send(join.bind, vat.address, i0, WETH.address)
    await send(port.bind, vat.address, RICO.address, true)
    await send(join.join, vat.address, i0, ALI, wad(1000))

    await send(vat.init, i0)
    await send(vat.file, b32('ceil'), rad(1000))
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
    const gembal = await vat.gem(i0, ALI)
    want(gembal.eq(wad(1000))).true
    const bal = await WETH.balanceOf(ALI)
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

  it('rejects unsafe frob', async () => {
    const [ink, art] = await vat.urns(i0, ALI)
    want(ink.toNumber()).to.eql(0)
    want(art.toNumber()).to.eql(0)
    await fail('Vat/not-safe', vat.frob, i0, ALI, ALI, ALI, 0, wad(1))
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

    const [,,mark1] = await vat.ilks(i0)
    want(mark1.eq(ray(1))).true

    const safe2 = await vat.callStatic.safe(i0, ALI)
    want(safe2).true

    await send(vat.plot, i0, ray(1).div(5))

    const safe3 = await vat.callStatic.safe(i0, ALI)
    want(safe3).false
  })
})
