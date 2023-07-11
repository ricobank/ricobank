const debug = require('debug')('rico:test')
import { expect as want } from 'chai'
import { task_total_gas } from './helpers'

import * as hh from 'hardhat'
// @ts-ignore
import { ethers } from 'hardhat'
import { constants } from 'ethers'

import { send, fail, N, wad, ray, rad, BANKYEAR, wait, warp, mine } from 'minihat'
const { hexZeroPad } = ethers.utils

import { b32, snapshot, revert } from './helpers'
const dpack = require('@etherpacks/dpack')

const bn2b32 = (bn) => hexZeroPad(bn.toHexString(), 32)
const i0 = Buffer.alloc(32) // ilk 0 id
const TAG = Buffer.from('feed'.repeat(16), 'hex')
const GASLIMIT = 100000000

describe('Vox', () => {
  let ali, bob, cat
  let ALI, BOB, CAT
  let fb
  let bank
  let ploker, weth, rico, risk
  let pack
  let deploygas

  before(async () => {
    [ali, bob, cat] = await ethers.getSigners();
    [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address)

    ;[deploygas, pack] = await task_total_gas(hh, 'deploy-ricobank', {mock:'true', netname: 'ethereum', tokens: './tokens.json'})
    const dapp = await dpack.load(pack, ethers, ali)

    fb = dapp.feedbase
    bank = dapp.bank
    ploker = dapp.ploker
    weth = dapp.weth
    rico = dapp.rico
    risk = dapp.risk

    await send(bank.file, b32("tag"), TAG)
    await send(bank.link, b32("tip"), ALI)

    await send(bank.file, b32("cap"), b32(ray(3)))

    await send(bank.file, b32('par'), b32(wad(7)))

    await send(bank.filhi, b32('weth'), b32('fsrc'), b32('weth'), ALI + '00'.repeat(12))
    await send(bank.filhi, b32('weth'), b32('ftag'), b32('weth'), b32('weth:rico'))
    await send(fb.push, b32('weth:rico'), bn2b32(ray(2000)), constants.MaxUint256);

    await send(bank.file, b32('flopsrc'), ALI + '00'.repeat(12))
    await send(bank.file, b32('floptag'), b32('risk:rico'))
    await send(bank.file, b32('flapsrc'), ALI + '00'.repeat(12))
    await send(bank.file, b32('flaptag'), b32('rico:risk'))
    await send(fb.push, b32('rico:risk'), bn2b32(ray(1)), constants.MaxUint256)
    await send(fb.push, b32('risk:rico'), bn2b32(ray(1)), constants.MaxUint256)

    await ali.sendTransaction({
      data: ethers.utils.id('deposit()').slice(0, 10), to: weth.address, value: wad(10)
    })
    await send(weth.approve, bank.address, constants.MaxUint256)
    await send(rico.approve, bank.address, constants.MaxUint256)
    await send(risk.approve, bank.address, constants.MaxUint256)
    await send(risk.mint, ALI, wad(100000));


    await snapshot(hh);
  })

  beforeEach(async () => {
    await revert(hh);
  })

  const gettime = async () => {
    const blocknum = await ethers.provider.getBlockNumber()
    return (await ethers.provider.getBlock(blocknum)).timestamp
  }

  it('ploke', async () => {
    for (const tag of ['weth:rico', 'rico:risk', 'risk:rico', 'rico:ref']) {
        debug(`ploking ${tag}`)
        await ploker.ploke(b32(tag))
    }
    await fail('ErrNoConfig', ploker.ploke, b32('ricoref'))
  })

  it('sway', async () => {
    let progress = 10 ** 10
    await send(bank.file, b32('par'), b32(wad(7)))

    await warp(hh, progress)
    await mine(hh)

    const t0 = await gettime()
    want(t0).equal(progress)

    await warp(hh, progress += 10)
    await mine(hh)

    const t1 = await gettime()
    want(t1).equal(10 ** 10 + 10)

    const par0 = await bank.par() // jammed to 7
    want(par0.eq(wad(7))).true

    await send(fb.push, TAG, bn2b32(wad(7)), t1 + 1000)

    await send(bank.poke)

    const par1 = await bank.par() // still at 7 because way == RAY
    want(par1.eq(wad(7))).true

    const t2 = await gettime()

    await send(bank.file, b32('way'), bn2b32(ray(2)))// doubles every second (!)
    await send(bank.poke)

    await warp(hh, progress += 10)
    await mine(hh)

    const par2 = await bank.par()
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

    await send(bank.file, b32('par'), b32(wad(1.24)))
    await send(bank.file, b32('how'), bn2b32(ray(1 + 1.2e-16)))

    await send(fb.push, TAG, bn2b32(wad(1.25)), 10 ** 12)
    await send(bank.poke)

    await warp(hh, t0 + 3600)
    await mine(hh)

    await send(bank.poke)
    const par2 = await bank.par()
    debug(par2.toString())

    await warp(hh, t0 + 2 * 3600)
    await mine(hh)

    await send(bank.poke)
    const par3 = await bank.par()
    debug(par3.toString())
  })

  describe('gas', () => {
    async function check(gas, minGas, maxGas?) {
      if (!maxGas) maxGas = minGas
      await want(gas.toNumber()).to.be.at.most(maxGas);
      if (gas.toNumber() < minGas) {
        console.log("gas reduction: previous min=", minGas, " gas used=", gas.toNumber());
      }
    }

    beforeEach(async () => {
      await send(bank.file, b32('par'), b32(ray(1)))
    })

    it('deploy gas', async () => {
      await check(ethers.BigNumber.from(deploygas), 40283751)
    })

    it('frob cold gas', async () => {
      let dink = ethers.utils.solidityPack(['int'], [wad(5)])
      let gas = await bank.estimateGas.frob(b32('weth'), ALI, dink, wad(5000))
      await check(gas, 269159)
    })

    it('frob hot gas', async () => {
      let dink = ethers.utils.solidityPack(['int'], [wad(5)])
      await send(bank.frob, b32('weth'), ALI, dink, wad(5000))
      let gas = await bank.estimateGas.frob(
        b32('weth'), ALI, ethers.utils.solidityPack(['int'], [wad(5)]), wad(5000)
      )
      await check(gas, 147654)
    })

    it('bail gas', async () => {
      let dink = ethers.utils.solidityPack(['int'], [wad(5)])
      await send(bank.frob, b32('weth'), ALI, dink, wad(5000))

      await send(fb.push, b32('weth:rico'), bn2b32(ray(800)), constants.MaxUint256)
      debug('bail')
      let gas = await bank.estimateGas.bail(b32('weth'), ALI)
      await check(gas, 221885, 221995)
    })

    it('keep surplus gas', async () => {
      let dink = ethers.utils.solidityPack(['int'], [wad(5)])
      await send(bank.frob, b32('weth'), ALI, dink, wad(5000))

      await mine(hh, BANKYEAR)
      await send(bank.drip, b32('weth'))

      let gas = await bank.estimateGas.keep([])
      await check(gas, 119562)
    })

    it('keep deficit gas', async() => {
      let dink = ethers.utils.solidityPack(['int'], [wad(5)])
      await send(bank.frob, b32('weth'), ALI, dink, wad(5000))
      await send(fb.push, b32('weth:rico'), bn2b32(ray(800)), constants.MaxUint256)
      await send(bank.bail, b32('weth'), ALI)

      let gas = await bank.estimateGas.keep([])
      await check(gas, 163482)
    })

    it('poke up gas', async () => {
      await mine(hh, 100)
      await send(fb.push, TAG, bn2b32(ray(0.5)), constants.MaxUint256)
      let gas = await bank.estimateGas.poke()
      await check(gas, 65089, 65340)
    })

    it('poke down gas', async () => {
      await mine(hh, 100)
      await send(fb.push, TAG, bn2b32(ray(2)), constants.MaxUint256)
      let gas = await bank.estimateGas.poke()
      await check(gas, 65109, 65340)
    })

    it('drip gas', async () => {
      let dink = ethers.utils.solidityPack(['int'], [wad(5)])
      await send(bank.frob, b32('weth'), ALI, dink, wad(5000))
      await mine(hh, BANKYEAR)
      let gas = await bank.estimateGas.drip(b32('weth'))
      await check(gas, 116225, 116235)
    })
  })
})
