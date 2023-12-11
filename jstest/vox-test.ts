const debug = require('debug')('rico:test')
import { expect as want } from 'chai'
import { task_total_gas } from './helpers'

import * as hh from 'hardhat'
// @ts-ignore
import { ethers } from 'hardhat'
import { constants } from 'ethers'

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


describe('Vox', () => {
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

    ;[deploygas, pack] = await task_total_gas(hh, 'deploy-ricobank', {mock:'true', netname: 'ethereum', tokens: './tokens.json'})
    dapp = await dpack.load(pack, ethers, ali)

    fb   = dapp.feedbase
    bank = dapp.bank
    ball = dapp.ball
    weth = dapp.weth
    rico = dapp.rico
    risk = dapp.risk
    dai  = dapp.dai

    await send(bank.file, b32("tip.tag"), TAG)
    await send(bank.file, b32("tip.src"), ALI + '00'.repeat(12))

    await send(bank.file, b32('par'), b32(wad(7)))

    await send(bank.filh, b32('weth'), b32('src'), [], ALI + '00'.repeat(12))
    await send(bank.filh, b32('weth'), b32('tag'), [], b32('weth:ref'))
    await send(fb.push, b32('weth:ref'), bn2b32(ray(0.8)), constants.MaxUint256);

    await send(bank.file, b32('rudd.src'), ALI + '00'.repeat(12))
    await send(bank.file, b32('rudd.tag'), b32('risk:rico'))
    await send(fb.push, b32('risk:rico'), bn2b32(ray(1)), constants.MaxUint256)

    await ali.sendTransaction({
      data: ethers.utils.id('deposit()').slice(0, 10), to: weth.address, value: wad(100)
    })
    await send(weth.approve, bank.address, constants.MaxUint256)
    await send(risk.mint, ALI, wad(100000));

    await send(bank.filk, b32(':uninft'), b32('line'), bn2b32(rad(10000)))


    await snapshot_name(hh);
  })

  beforeEach(async () => revert_name(hh))
  after(async () => {
      revert_pop(hh)
      revert_clear(hh)
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

    let cap = await bank.cap()
    await send(bank.file, b32('way'), bn2b32(cap))
    await send(bank.poke)

    await warp(hh, progress += BANKYEAR)
    await mine(hh)
    await send(bank.poke)

    const par2 = await bank.par()
    want(par2.gt(wad(13.9))).true
    want(par2.lt(wad(14.1))).true
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
      await check(ethers.BigNumber.from(deploygas), 37580733)
    })

    it('frob cold gas', async () => {
      let dink = ethers.utils.solidityPack(['int'], [wad(5)])
      let gas = await bank.estimateGas.frob(b32('weth'), ALI, dink, wad(2))
      await check(gas, 345268, 345294)
    })

    it('frob hot gas', async () => {
      let dink = ethers.utils.solidityPack(['int'], [wad(5)])
      await send(bank.frob, b32('weth'), ALI, dink, wad(2))
      await mine(hh, 100)
      await send(bank.drip, b32('weth'))
      let gas = await bank.estimateGas.frob(
        b32('weth'), ALI, ethers.utils.solidityPack(['int'], [wad(5)]), wad(2)
      )
      await check(gas, 190993)
    })

    it('bail gas', async () => {
      let dink = ethers.utils.solidityPack(['int'], [wad(5)])
      await send(bank.frob, b32('weth'), ALI, dink, wad(2))

      await send(fb.push, b32('weth:ref'), bn2b32(ray(0.1)), constants.MaxUint256)
      debug('bail')
      let gas = await bank.estimateGas.bail(b32('weth'), ALI)
      await check(gas, 237007)
    })

    it('keep surplus gas', async () => {
      let dink = ethers.utils.solidityPack(['int'], [wad(5)])
      await send(bank.frob, b32('weth'), ALI, dink, wad(1))
      await send(fb.push, b32('weth:ref'), bn2b32(ray(0)), constants.MaxUint256)
      await send(bank.bail, b32('weth'), ALI)
      await send(fb.push, b32('weth:ref'), bn2b32(ray(1)), constants.MaxUint256)
      await send(bank.frob, b32('weth'), ALI, dink, wad(4))

      await mine(hh, BANKYEAR * 100)
      await send(bank.drip, b32('weth'))

      let gas = await bank.estimateGas.keep([])
      await check(gas, 121597)
    })

    it('keep deficit gas', async() => {
      let dink = ethers.utils.solidityPack(['int'], [wad(5)])
      await send(bank.frob, b32('weth'), ALI, dink, wad(2))
      await send(fb.push, b32('weth:ref'), bn2b32(ray(0.1)), constants.MaxUint256)
      await send(bank.bail, b32('weth'), ALI)

      let gas = await bank.estimateGas.keep([])
      await check(gas, 129884)
    })

    it('poke up gas', async () => {
      await mine(hh, 100)
      await send(fb.push, TAG, bn2b32(ray(0.5)), constants.MaxUint256)
      let gas = await bank.estimateGas.poke()
      await check(gas, 68616, 69450)
    })

    it('poke down gas', async () => {
      await mine(hh, 100)
      await send(fb.push, TAG, bn2b32(ray(2)), constants.MaxUint256)
      let gas = await bank.estimateGas.poke()
      await check(gas, 69109, 69943)
    })

    it('read mar gas', async () => {
      let mar_tag = b32('rico:ref')
      let divider = await ball.divider()
      let mar_gas = await fb.estimateGas.pull(divider, mar_tag)
      await check(mar_gas, 148278)
    })

    it('drip gas', async () => {
      let dink = ethers.utils.solidityPack(['int'], [wad(5)])
      await send(bank.frob, b32('weth'), ALI, dink, wad(2))
      await mine(hh, BANKYEAR)
      let gas = await bank.estimateGas.drip(b32('weth'))
      await check(gas, 91723)
    })

    describe('uni nft gas', async () => {

      let ricodaitokids = []
      before(async () => {
        const apad = (addr) => {
          return addr + '00'.repeat(12)
        }
        await send(bank.filh, b32(':uninft'), b32('src'), [apad(dai.address)], apad(ALI))
        await send(bank.filh, b32(':uninft'), b32('tag'), [apad(dai.address)], b32('dai:ref'))
        await send(bank.filh, b32(':uninft'), b32('liqr'), [apad(dai.address)], bn2b32(ray(1)))
        await send(fb.push, b32('dai:ref'), bn2b32(ray(1)), constants.MaxUint256)

        await send(bank.filh, b32(':uninft'), b32('src'),[apad(rico.address)], apad(ALI))
        await send(bank.filh, b32(':uninft'), b32('tag'), [apad(rico.address)], b32('rico:ref'))
        await send(bank.filh, b32(':uninft'), b32('liqr'), [apad(rico.address)], bn2b32(ray(1)))
        await send(fb.push, b32('rico:ref'), bn2b32(ray(0.8)), constants.MaxUint256)

        let amt = wad(10)
        const encode = ethers.utils.defaultAbiCoder.encode
        let dink = ethers.utils.defaultAbiCoder.encode(['uint'], [wad(50)])
        await send(bank.frob, b32('weth'), ALI, dink, amt.mul(3))

        const whale = await ethers.getImpersonatedSigner(
            '0x075e72a5eDf65F0A5f44699c7654C1a76941Ddc8'
        );
        await send(dai.connect(whale).transfer, ALI, amt.mul(3))

        for (let i = 0; i < 3; i++) {
            let joinres = await join_pool({
                nfpm: dapp.nonfungiblePositionManager, ethers, ali,
                a1: { token: rico.address, amountIn: amt },
                a2: { token: dai.address,  amountIn: amt },
                fee: 500,
                tickSpacing: 10
            })
            await send(dapp.nonfungiblePositionManager.approve, bank.address, joinres.tokenId)
            ricodaitokids.push(joinres.tokenId)
        }

        await snapshot_name(hh)
      })

      beforeEach(async () => { await revert_name(hh) })
      after(async () => { await revert_pop(hh) })

      it('uni nft frob down gas', async () => {
        let dink = ethers.utils.defaultAbiCoder.encode(['uint[]'], [[1].concat(ricodaitokids)]);
        await send(bank.frob, b32(':uninft'), ALI, dink, wad(10))

        // partial wipe so slots are hot and avoids setting art to 0
        dink = ethers.utils.defaultAbiCoder.encode(
          ['uint[]'], [[constants.MaxUint256, ricodaitokids[2], ricodaitokids[1]]]
        )
        let gas = await bank.estimateGas.frob(b32(':uninft'), ALI, dink, wad(-9))
 
        await check(gas, 454528)
      })

      it('uni nft frob up gas', async () => {
        let dink = ethers.utils.defaultAbiCoder.encode(['uint[]'], [[1].concat(ricodaitokids)]);
        await send(bank.frob, b32(':uninft'), ALI, dink, wad(10))

        // partial wipe so slots are hot and avoids setting art to 0
        dink = ethers.utils.defaultAbiCoder.encode(
          ['uint[]'], [[constants.MaxUint256, ricodaitokids[2], ricodaitokids[1]]]
        )
        let gas = await bank.estimateGas.frob(b32(':uninft'), ALI, dink, wad(1))
 
        await check(gas, 458078)
      })

      it('uni nft bail gas', async () => {
        let dink = ethers.utils.defaultAbiCoder.encode(['uint[]'], [[1].concat(ricodaitokids)]);
        await send(bank.frob, b32(':uninft'), ALI, dink, wad(10))

        // make somewhat unsafe (but not 0)
        await send(fb.push, b32('dai:ref'), bn2b32(constants.Zero), constants.MaxUint256)
        await send(fb.push, b32('rico:ref'), bn2b32(constants.Zero), constants.MaxUint256)

        let gas = await bank.estimateGas.bail(b32(':uninft'), ALI)
        await check(gas, 637772)
      })
    })
  })
})
