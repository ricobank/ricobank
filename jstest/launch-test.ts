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
  let ali, ALI, fb, bank, weth, usdc, pack, dapp, cla, unia, nfpm, riskaddr

  before(async () => {
    ;[ali] = await ethers.getSigners()
    ALI = ali.address

    const gfpack = await hh.run('deploy-gemfab')
    const gfpackcid = await dpack.putIpfsJson(gfpack)
    const gf = (await dpack.load(gfpack, ethers, ali)).gemfab
    riskaddr = await gf.callStatic.build(b32('RISK'), b32('RISK'))
    await send(gf.build, b32('RISK'), b32('RISK'))

    const aggpackcid = 'bafkreidz647bfb36naoib7mbshpiowmz5rhnh6sjhy4aenzqxkb3rjyvsm'

    pack = await hh.run('deploy-ricobank', {netname: 'ethereum', tokens: './tokens-launch.json', writepack: 'true', gfpackcid, risk: riskaddr, aggpackcid})
    dapp = await dpack.load(pack, ethers, ali)

    fb   = dapp.feedbase
    bank = dapp.bank
    weth = dapp.weth
    usdc = dapp.usdc
    cla  = dapp.chainlinkadapter
    nfpm = dapp.nonfungiblePositionManager
    unia = dapp.uniswapv3adapter

    await ali.sendTransaction({
      data: ethers.utils.id('deposit()').slice(0, 10), to: weth.address, value: wad(100)
    })

    await send(weth.approve, bank.address, constants.MaxUint256)

    let config = await cla.getConfig(b32('weth:usd'))
    await cla.setConfig(b32('weth:usd'), [config.agg, '3000000000000000000000000'])
    config = await cla.getConfig(b32('usdc:eth'))
    await cla.setConfig(b32('usdc:eth'), [config.agg, '3000000000000000000000000'])
    config = await cla.getConfig(b32('usdc:usd'))
    await cla.setConfig(b32('usdc:usd'), [config.agg, '3000000000000000000000000'])

    await snapshot_name(hh);
  })

  afterEach(async () => revert_name(hh))
  after(async () => {
    revert_pop(hh)
    revert_clear(hh)
  })

  describe('read price', () => {

    const testread = (i, lo, hi) => {
      it(`read ${i} price`, async () => {
        const src = (await bank.geth(b32(i), b32('src'), [])).slice(0, 42)
        const tag = await bank.geth(b32(i), b32('tag'), [])
        const mar = BN.from((await fb.pull(src, tag)).val)
        if (mar.lt(lo)) {
          throw new Error(`expected ${mar} >= ${lo}`)
        }
        if (mar.gt(hi)) {
          throw new Error(`expected ${mar} <= ${hi}`)
        }
      })
    }

    testread('reth', ray(1.2), ray(1.5)) // ~1.1 * 2300 / 2000
    testread('dai', ray(1).div(2100), ray(1).div(1900)) // ~1 / 2000
    testread('usdc',
             ray(0.95).div(2000).mul(10 ** 12),
             ray(1.05).div(2000).mul(10 ** 12)) // ~1 / 2000
    testread('wbtc',
             ray(19).mul(10 ** 10),
             ray(21).mul(10 ** 10)) // ~ 40000 / 2000, 8 decimals
    testread('weth', ray(1.1), ray(1.3)) // ~ 2300 / 2000
    testread('link', ray(0.007), ray(0.008)) // ~ 14 / 2000
  })

  describe('basic frob', () => {
    const testfrob = (i, whale) => {
      it(`transfer ok on frob ${i}`, async () => {
        if (whale != ALI) {
          await hh.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [whale],
          });

          const wallet = await ethers.getSigner(whale)
          const whaledapp = await dpack.load(pack, ethers, wallet)
          await send(whaledapp[i].transfer, ALI, 1)
          await hh.network.provider.request({
            method: "hardhat_stopImpersonatingAccount",
            params: [whale],
          });
        }

        await send(dapp[i].approve, bank.address, 1)
        let dink = ethers.utils.defaultAbiCoder.encode(['int'], [1])
        await send(bank.frob, b32(i), ALI, dink, 0)
        dink = ethers.utils.defaultAbiCoder.encode(['int'], [constants.Zero.sub(1)])
        await send(bank.frob, b32(i), ALI, dink, 0)
      })
    }

    testfrob('reth', '0x714301eB35fE043FAa547976ce15BcE57BD53144')
    testfrob('dai', '0x075e72a5eDf65F0A5f44699c7654C1a76941Ddc8')
    testfrob('usdc', '0xD6153F5af5679a75cC85D8974463545181f48772')
    testfrob('wbtc', '0x6daB3bCbFb336b29d06B9C793AEF7eaA57888922')
    testfrob('weth', '0x8EB8a3b98659Cce290402893d0123abb75E3ab28')
    testfrob('link', '0xF977814e90dA44bFA03b6295A0616a897441aceC')
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

  it('uni weth:usdc pool', async () => {

    // impersonate some whale to get some usdc
    const WHALE = "0xD6153F5af5679a75cC85D8974463545181f48772"
    await hh.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [WHALE],
    });
    const whale = await ethers.getSigner(WHALE)
    const whaledapp = await dpack.load(pack, ethers, whale)
    await send(whaledapp.usdc.transfer, ALI, '120000000000')
    await hh.network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [WHALE],
    });

    const joinres = await join_pool({
      nfpm: nfpm, ethers, ali,
      a1: { token: weth.address, amountIn: wad(50) },
      a2: { token: usdc.address,  amountIn: '120000000000' },
      fee: 500,
      tickSpacing: 10
    })

    await send(nfpm.approve, bank.address, joinres.tokenId)
    const encode = ethers.utils.defaultAbiCoder.encode
    let dink = ethers.utils.defaultAbiCoder.encode(['uint[]'], [[1, joinres.tokenId]])

    await send(bank.frob, b32(':uninft'), ALI, dink, wad(100))
  })
})
