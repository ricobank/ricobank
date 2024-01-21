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

const bn2b32 = (bn) => hexZeroPad(bn.toHexString(), 32)
const TAG = Buffer.from('feed'.repeat(16), 'hex')

const gettime = async () => {
    const blocknum = await ethers.provider.getBlockNumber()
    return (await ethers.provider.getBlock(blocknum)).timestamp
}

const join_pool = async (args) => {
    let nfpm = args.nfpm
    let ethers = args.ethers
    let ali = args.ali
    debug('join_pool')
    if (ethers.BigNumber.from(args.a1.token).gt(ethers.BigNumber.from(args.a2.token))) {
      let a = args.a1;
      args.a1 = args.a2;
      args.a2 = a;
    }

    let spacing = args.tickSpacing;
    let tickmax = 887220
    // full range liquidity
    let tickLower = -tickmax;
    let tickUpper = tickmax;
    let token1 = await ethers.getContractAt('Gem', args.a1.token)
    let token2 = await ethers.getContractAt('Gem', args.a2.token)
    debug('approve tokens ', args.a1.token, args.a2.token)
    await send(token1.approve, nfpm.address, ethers.constants.MaxUint256);
    await send(token2.approve, nfpm.address, ethers.constants.MaxUint256);
    let timestamp = await gettime()
    debug('nfpm mint', nfpm.address)
    let [tokenId, liquidity, amount0, amount1] = await nfpm.callStatic.mint([
          args.a1.token, args.a2.token,
          args.fee,
          tickLower, tickUpper,
          args.a1.amountIn, args.a2.amountIn,
          0, 0, ali.address, timestamp + 1000
    ]);

    await send(nfpm.mint, [
          args.a1.token, args.a2.token,
          args.fee,
          tickLower, tickUpper,
          args.a1.amountIn, args.a2.amountIn,
          0, 0, ali.address, timestamp + 1000
    ]);

    return {tokenId, liquidity, amount0, amount1}
}


describe('Launch', () => {
  let ali, bob, cat
  let ALI, BOB, CAT
  let fb
  let bank, ball
  let weth, rico, risk
  let pack
  let deploygas
  let dapp
  let dai

  before(async () => {
    [ali, bob, cat] = await ethers.getSigners();
    [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address)

    ;[deploygas, pack] = await task_total_gas(hh, 'deploy-ricobank', {netname: 'ethereum', tokens: './tokens.json', writepack: 'true'})
    dapp = await dpack.load(pack, ethers, ali)

    fb   = dapp.feedbase
    bank = dapp.bank
    ball = dapp.ball
    weth = dapp.weth
    rico = dapp.rico
    risk = dapp.risk
    dai  = dapp.dai

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
