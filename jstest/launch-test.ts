const debug = require('debug')('rico:test')
import { expect as want } from 'chai'
import { task_total_gas } from './helpers'

import * as hh from 'hardhat'
// @ts-ignore
import { ethers } from 'hardhat'
import { constants, BigNumber as BN } from 'ethers'

import { send, fail, wad, ray, rad, BANKYEAR, warp, mine } from 'minihat'
const { hexZeroPad } = ethers.utils

import { b32, revert_pop, revert_name, revert_clear, snapshot_name, join_pool } from './helpers'
const dpack = require('@etherpacks/dpack')

const rpaddr = (a) => a + '00'.repeat(12)

describe('Launch', () => {
  let ali, ALI, fb, bank, weth, wsteth, pack, dapp, cla, unia, nfpm, riskaddr

  before(async () => {
    ;[ali] = await ethers.getSigners()
    ALI = ali.address

    const gfpack = await hh.run('deploy-gemfab')
    const gfpackcid = await dpack.putIpfsJson(gfpack)
    const gf = (await dpack.load(gfpack, ethers, ali)).gemfab
    riskaddr = await gf.callStatic.build(b32('RISK'), b32('RISK'))
    await send(gf.build, b32('RISK'), b32('RISK'))

    pack = await hh.run('deploy-ricobank', {netname: 'ethereum', tokens: './tokens.json', writepack: 'true', gfpackcid, risk: riskaddr})
    dapp = await dpack.load(pack, ethers, ali)

    fb   = dapp.feedbase
    bank = dapp.bank
    weth = dapp.weth
    wsteth = dapp.wsteth
    cla  = dapp.chainlinkadapter
    nfpm = dapp.nonfungiblePositionManager
    unia = dapp.uniswapv3adapter

    await ali.sendTransaction({
      data: ethers.utils.id('deposit()').slice(0, 10), to: weth.address, value: wad(100)
    })

    await send(weth.approve, bank.address, constants.MaxUint256)

    const config = await cla.getConfig(b32('weth:usd'))
    await cla.setConfig(b32('weth:usd'), [config.agg, '3000000000000000000000000'])
    await cla.setConfig(b32('wsteth:eth'), [config.agg, '3000000000000000000000000'])
    await cla.setConfig(b32('usdc:usd'), [config.agg, '3000000000000000000000000'])

    await snapshot_name(hh);
  })

  afterEach(async () => revert_name(hh))
  after(async () => {
    revert_pop(hh)
    revert_clear(hh)
  })

  it('read usdc price', async () => {
    const src = (await bank.geth(b32('usdc'), b32('src'), [])).slice(0, 42)
    const tag = await bank.geth(b32('usdc'), b32('tag'), [])
    const mar = await fb.pull(src, tag)
    want(BN.from(mar.val).gt(ray(0.95).mul(10 ** 12))).true
    want(BN.from(mar.val).lt(ray(1.05).mul(10 ** 12))).true
  })

  it('weth', async () => {
    want(riskaddr).eql(dapp.risk.address)

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

  it('uni weth:wsteth pool', async () => {

    // impersonate some whale to get some wsteth
    const WHALE = "0x0F8179A26ae4709EC59048a266E690d49553605A"
    await hh.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [WHALE],
    });
    const whale = await ethers.getSigner(WHALE)
    const whaledapp = await dpack.load(pack, ethers, whale)
    await send(whaledapp.wsteth.transfer, ALI, wad(50))
    await hh.network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [WHALE],
    });

    const joinres = await join_pool({
      nfpm: nfpm, ethers, ali,
      a1: { token: weth.address, amountIn: wad(50) },
      a2: { token: wsteth.address,  amountIn: wad(50) },
      fee: 500,
      tickSpacing: 10
    })

    await send(nfpm.approve, bank.address, joinres.tokenId)
    const encode = ethers.utils.defaultAbiCoder.encode
    let dink = ethers.utils.defaultAbiCoder.encode(['uint[]'], [[1, joinres.tokenId]])

    await send(bank.frob, b32(':uninft'), ALI, dink, wad(100))
  })
})
