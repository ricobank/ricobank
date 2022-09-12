const debug = require('debug')('rico:test')
import { expect as want } from 'chai'

import * as hh from 'hardhat'
// @ts-ignore
import { ethers } from 'hardhat'

import { send, N, wad, ray, rad, BANKYEAR, wait, warp, mine } from 'minihat'
const { hexZeroPad } = ethers.utils

import { b32, snapshot, revert } from './helpers'
const dpack = require('@etherpacks/dpack')

const bn2b32 = (bn) => hexZeroPad(bn.toHexString(), 32)
const i0 = Buffer.alloc(32) // ilk 0 id
const TAG = Buffer.from('feed'.repeat(16), 'hex')

describe('Vox', () => {
  let ali, bob, cat
  let ALI, BOB, CAT
  let vat
  let vox
  let fb

  before(async () => {
    [ali, bob, cat] = await ethers.getSigners();
    [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address)
    const pack = await hh.run('deploy-ricobank', { mock: 'true' })
    const dapp = await dpack.load(pack, ethers, ali)

    vat = dapp.vat
    vox = dapp.vox
    fb = dapp.feedbase

    await send(vox.file, b32("tag"), TAG)

    await send(vox.file, b32("cap"), bn2b32(ray(3)))

    await send(vat.prod, wad(7))

    await snapshot(hh);
  })

  beforeEach(async () => {
    await revert(hh);
  })

  const gettime = async () => {
    const blocknum = await ethers.provider.getBlockNumber()
    return (await ethers.provider.getBlock(blocknum)).timestamp
  }

  it('sway', async () => {
    let progress = 10 ** 10
    await send(vat.prod, wad(7))

    await warp(hh, progress)
    await mine(hh)

    const t0 = await gettime()
    want(t0).equal(progress)

    await warp(hh, progress += 10)
    await mine(hh)

    const t1 = await gettime()
    want(t1).equal(10 ** 10 + 10)

    const par0 = await vat.par() // jammed to 7
    want(par0.eq(wad(7))).true

    await send(fb.push, TAG, bn2b32(wad(7)), t1 + 1000)

    await send(vox.poke)

    const par1 = await vat.par() // still at 7 because way == RAY
    want(par1.eq(wad(7))).true

    const t2 = await gettime()

    await send(vox.file, b32('way'), bn2b32(ray(2)))// doubles every second (!)
    await send(vox.poke)

    await warp(hh, progress += 10)
    await mine(hh)

    const par2 = await vat.par()
    want(par2.eq(wad(28))).true
  })

  it('ricolike vox', async () => {
    const t0 = 10 ** 11
    await warp(hh, t0)
    await mine(hh)
    const t10 = t0 + 10
    await warp(hh, t10)
    await mine(hh, )
    const t10_ = await gettime()
    want(t10_).equals(t10)

    await send(vat.prod, wad(1.24))
    await send(vox.file, b32('how'), bn2b32(ray(1 + 1.2e-16)))

    await send(fb.push, TAG, bn2b32(wad(1.25)), 10 ** 12)
    await send(vox.poke)

    await warp(hh, t0 + 3600)
    await mine(hh)

    await send(vox.poke)
    const par2 = await vat.par()
    debug(par2.toString())

    await warp(hh, t0 + 2 * 3600)
    await mine(hh)

    await send(vox.poke)
    const par3 = await vat.par()
    debug(par3.toString())
  })
})
