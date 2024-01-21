const debug = require('debug')('rico:test')
import { expect as want } from 'chai'
import { task_total_gas } from './helpers'

import * as hh from 'hardhat'
// @ts-ignore
import { ethers } from 'hardhat'
import { constants, BigNumber as BN } from 'ethers'

import { send, fail, wad, ray, rad, BANKYEAR, warp, mine } from 'minihat'
const { hexZeroPad } = ethers.utils

import { b32, revert_pop, revert_name, revert_clear, snapshot_name } from './helpers'
const dpack = require('@etherpacks/dpack')

describe('Launch', () => {
  let ali, ALI, fb, bank, weth, pack, dapp

  before(async () => {
    ;[ali] = await ethers.getSigners()
    ALI = ali.address

    pack = await hh.run('deploy-ricobank', {netname: 'ethereum', tokens: './tokens.json', writepack: 'true'})
    dapp = await dpack.load(pack, ethers, ali)

    fb   = dapp.feedbase
    bank = dapp.bank
    weth = dapp.weth

    await ali.sendTransaction({
      data: ethers.utils.id('deposit()').slice(0, 10), to: weth.address, value: wad(100)
    })

    await send(weth.approve, bank.address, constants.MaxUint256)
 

    await snapshot_name(hh);
  })

  afterEach(async () => revert_name(hh))
  after(async () => {
    revert_pop(hh)
    revert_clear(hh)
  })

  it('launch', async () => {
    let tip = await bank.tip()
    let mar = await fb.pull(tip.src, tip.tag)
    want(BN.from(mar.val).gt(ray(0.9))).true
    want(BN.from(mar.val).lt(ray(1.1))).true
    const timestamp = (await ethers.provider.getBlock('latest')).timestamp
    want(mar.ttl.gt(timestamp)).true

    want(await bank.way()).eql(ray(1))
    await send(bank.poke)
    want((await bank.way()).lt(ray(1))).true

    let dink = ethers.utils.defaultAbiCoder.encode(['uint'], [wad(50)])
    await send(bank.frob, b32('weth'), ali.address, dink, wad(40))

    await warp(hh, timestamp + BANKYEAR)
    await send(bank.poke)
    want((await bank.way()).lt(ray(1))).true

    await send(bank.frob, b32('weth'), ali.address, dink, wad(25))
  })
})
