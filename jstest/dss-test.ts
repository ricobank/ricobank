import { expect as want, assert } from 'chai'

import * as hh from 'hardhat'
// @ts-ignore
import { ethers } from 'hardhat'

import { fail, send, wad, ray, rad, N, U256_MAX, warp, fxp } from 'minihat'
import { BigNumber, constants } from 'ethers'

import { RICO_mint, snapshot_name, revert_name, revert_pop, revert_clear, b32, curb_ramp } from './helpers'
const bn2b32 = (bn) => hexZeroPad(bn.toHexString(), 32)

const { hexZeroPad } = ethers.utils

const debug = require('debug')('rico:test')

const dpack = require('@etherpacks/dpack')
import { smock } from '@defi-wonderland/smock'
require('chai').use(smock.matchers);

const i0 = Buffer.alloc(32) // ilk 0 id
const tag = b32('GEMUSD')

const gettime = async () => {
  const blocknum = await ethers.provider.getBlockNumber()
  return (await ethers.provider.getBlock(blocknum)).timestamp
}

describe('dss', () => {
  let ali, bob, cat, dan, me
  let ALI, BOB, CAT, DAN, ME
  let vat; let vat_type
  let joy, gem; let gem_type
  let flower, flower_type
  let dock
  let vow, vow_type
  let vault, vault_type
  let fb
  let t1

  let RICO, RISK
  //let poolId_weth_rico
  let poolId_gem_rico
  let poolId_risk_rico
  const total_pool_rico = 10000
  const total_pool_risk = 10000
  const ceil = total_pool_rico + 300
  before(async () => {
    //this.timeout(100000);
    [me, ali, bob, cat, dan] = await ethers.getSigners();
    [ME, ALI, BOB, CAT, DAN] = [me, ali, bob, cat, dan].map(signer => signer.address)
    //me = ali
    //ME = ALI
    await snapshot_name(hh)

    const pack = await hh.run('deploy-ricobank', { mock: 'true' })
    const dapp = await dpack.load(pack, ethers, me)
    //vow = dapp.vow
    vat = dapp.vat
    RICO = joy = dapp.rico
    RISK = dapp.risk
    dock = dapp.dock
    fb   = dapp.feedbase

    t1 = await gettime()

    // Mock vault takes less time to create
    vault_type = await ethers.getContractFactory('MockBalancerV2Vault', me)
    vault = await vault_type.deploy()

    const gem_artifacts = require('../lib/gemfab/artifacts/src/gem.sol/Gem.json')
    gem_type = ethers.ContractFactory.fromSolidity(gem_artifacts, me)
    gem = await gem_type.deploy(b32('Gem'), b32('GEM'))

    await send(vat.ward, dock.address, true)
    await send(gem.approve, dock.address, U256_MAX)

    await send(dock.bind_gem, vat.address, i0, gem.address)
    await send(dock.bind_joy, vat.address, joy.address, true)

    debug('vat init')
    await send(vat.init, i0, gem.address, ME, tag)
    await send(vat.file, b32('ceil'), rad(ceil))
    await send(vat.filk, i0, b32('line'), rad(1000))

    await send(fb.push, tag, bn2b32(ray(1)), t1 + 1000)

    flower_type = await smock.mock('BalancerFlower', { signer: me })
    flower = await flower_type.deploy()
    debug(`created flower @ ${flower.address}`)

    vow_type = await smock.mock('Vow', { signer: me })
    vow = await vow_type.deploy()
    await me.sendTransaction({to: vow.address, value: ethers.utils.parseEther('1.0')})
    debug(`created vow @ ${vow.address}`)

    await send(gem.approve, vault.address, U256_MAX)
    await send(RICO.approve, vault.address, U256_MAX)
    await send(RISK.approve, vault.address, U256_MAX)
    await send(gem.approve, flower.address, constants.MaxUint256)
    await send(RICO.approve, flower.address, constants.MaxUint256)
    await send(RISK.approve, flower.address, constants.MaxUint256)

    const gemBal = Math.floor(40/110 * total_pool_rico)
    const ricoBal = total_pool_rico
    const riskBal = total_pool_risk

    debug('minting tokens for balancer pools')
    await send(gem.mint, ME, wad(gemBal)) // flip rico supply/gem supply = 110/40
    await send(vat.ward, dock.address, true)
    await send(RICO.ward, dock.address, true)
    await RICO_mint(vat, dock, RICO, me, ricoBal)

    await send(RISK.mint, ME, wad(total_pool_risk))

    await send(gem.transfer, vault.address, wad(gemBal))
    await send(RICO.transfer, vault.address, wad(ricoBal))
    await send(RISK.transfer, vault.address, wad(riskBal))
    await send(vault.setPrice, gem.address, RICO.address, wad(ricoBal / gemBal))
    await send(vault.setPrice, RICO.address, gem.address, wad(gemBal / ricoBal))
    await send(vault.setPrice, RISK.address, RICO.address, wad(ricoBal / riskBal))
    await send(vault.setPrice, RICO.address, RISK.address, wad(riskBal / ricoBal))

    poolId_gem_rico  = Buffer.from('11'.repeat(32), 'hex')
    poolId_risk_rico = Buffer.from('22'.repeat(32), 'hex')

    want(await gem.balanceOf(ME)).to.eql(wad(0))
    want(await RICO.balanceOf(ME)).to.eql(wad(0))
    want(await RISK.balanceOf(ME)).to.eql(wad(0))

    debug('connecting flower')
    await send(vow.link, b32('RICO'), RICO.address)
    await send(vow.link, b32('RISK'), RISK.address)
    await send(vow.link, b32('vat'), vat.address)
    await send(flower.setVault, vault.address)
    await send(flower.approve_gem, gem.address)
    await send(flower.setPool, gem.address,  RICO.address, poolId_gem_rico)
    await send(flower.setPool, RISK.address,  RICO.address, poolId_risk_rico)
    await send(flower.setPool, RICO.address,  RISK.address, poolId_risk_rico)

    debug('link flow to vow')
    await send(vow.link, b32('flow'), flower.address)
    await send(vow.grant, gem.address)

    debug('link vat to vow')
    await send(vow.link, b32('vat'), vat.address)
    debug('link port, plug to vow')
    await send(vow.link, b32('dock'), dock.address)
    await send(flower.ward, vow.address, true)
    await send(vow.ward, flower.address, true)
    await send(vow.ward, dock.address, true)

    debug('link rico, risk to vow')
    await send(vow.link, b32('RICO'), RICO.address)
    await send(vow.link, b32('RISK'), RISK.address)
    await send(vow.grant, RICO.address)
    await send(vow.grant, RISK.address)

    debug('risk ward vow')
    await send(RISK.ward, vow.address, true)
    debug('rico ward port')
    await send(RICO.ward, dock.address, true)

    debug('vat ward, hope vow')
    await send(vat.ward, vow.address, true)

    await snapshot_name(hh)
  })
  afterEach(async () => {
    await revert_name(hh)
  })
  after(async () => {
    await revert_pop(hh)
    await revert_clear(hh)
  })

  describe('vat', () => {

    const _ink = async (ilk, usr) => {
      const [ink,] = await vat.urns(ilk, usr)
      return ink
    }
    const _art = async (ilk, usr) => {
      const [,art] = await vat.urns(ilk, usr)
      return art
    }
    const _gem = async (ilk, usr) => {
      return vat.gem(ilk, usr)
    }

    describe('frob', () => {
      before(async () => {
        want(await vat.gem(i0, ME)).to.eql(constants.Zero) // unpluged
        want(await gem.balanceOf(ME)).to.eql(constants.Zero)
        await send(gem.mint, ME, wad(1000))
        await send(dock.join_gem, vat.address, i0, ME, wad(1000))
        await send(fb.push, tag, bn2b32(ray(1)), t1 + 1000)
        await send(vat.filk, i0, b32('line'), rad(1000))
        await send(vat.file, b32('ceil'), rad(ceil))
        await send(RICO.ward, dock.address, true)
        await snapshot_name(hh)
      })
      after(async () => { await revert_pop(hh) })
      afterEach(async () => { await revert_name(hh) })

      it('test_setup', async () => {
        want(await gem.balanceOf(dock.address)).to.eql(wad(1000))
        want(await vat.gem(i0, ME)).to.eql(wad(1000))
      })

      it('test_plug', async () => {
        // urn  == (ALI, ilk)
        // gold == gem
        // i0 ~ 'gold'
        await send(gem.mint, ME, wad(500))
        want(await gem.balanceOf(ME)).to.eql(wad(500))
        want(await gem.balanceOf(dock.address)).to.eql(wad(1000))
        await send(dock.join_gem, vat.address, i0, ME, wad(500))
        want(await gem.balanceOf(ME)).to.eql(wad(0))
        want(await gem.balanceOf(dock.address)).to.eql(wad(1500))
        await send(dock.exit_gem, vat.address, i0, ME, wad(250))
        want(await gem.balanceOf(ME)).to.eql(wad(250))
        want(await gem.balanceOf(dock.address)).to.eql(wad(1250))
      })

      it('test_lock', async () => {
        want(await _ink(i0, ME)).to.eql(constants.Zero)
        want(await vat.gem(i0, ME)).to.eql(wad(1000))
        await send(vat.frob, i0, ME, wad(6), wad(0))
        want(await _ink(i0, ME)).to.eql(wad(6))
        want(await vat.gem(i0, ME)).to.eql(wad(994))
        await send(vat.frob, i0, ME, wad(-6), wad(0))
        want(await _ink(i0, ME)).to.eql(constants.Zero)
        want(await vat.gem(i0, ME)).to.eql(wad(1000))
      })

      it('test_calm', async () => {
        // calm means that the debt ceiling is not exceeded
        // it's ok to increase debt as long as you remain calm
        await send(vat.filk, i0, b32('line'), rad(10)) // filk ~ dss file
        await send(vat.frob, i0, ME, wad(10), wad(9))
        debug('only if under debt ceiling')
        await fail('ErrDebtCeil', vat.frob, i0, ME, wad(0), wad(2))
      })

      it('test_cool', async () => {
        // cool means that the debt has decreased
        // it's ok to be over the debt ceiling as long as you're cool
        await send(vat.filk, i0, b32('line'), rad(10))
        await send(vat.frob, i0, ME, wad(10), wad(8))
        await send(vat.filk, i0, b32('line'), rad(5))
        debug('can decrease debt when over ceiling')
        await send(vat.frob, i0, ME, wad(0), wad(-1))
      })

      it('test_safe', async () => {
        // safe means that the cdp is not risky
        // you can't frob a cdp into unsafe
        await send(vat.frob, i0, ME, wad(10), wad(5))
        await fail('ErrNotSafe', vat.frob, i0, ME, wad(0), wad(6))
      })

      it('test_nice', async () => {
        // nice means that the collateral has increased or the debt has
        // decreased. remaining unsafe is ok as long as you're nice

        await send(vat.frob, i0, ME, wad(10), wad(10))
        await send(fb.push, tag, bn2b32(ray(0.5)), t1 + 1000)
        debug('debt can\'t increase if unsafe')
        await fail('ErrNotSafe', vat.frob, i0, ME, wad(0), wad(1))
        debug('debt can decrease')
        await send(vat.frob, i0, ME, wad(0), wad(-1))
        debug('ink can\'t decrease')
        await fail('ErrNotSafe', vat.frob, i0, ME, wad(-1), wad(0))
        debug('ink can increase')
        await send(vat.frob, i0, ME, wad(1), wad(0))

        debug('cdp is still unsafe')
        debug('ink can\'t decrease, even if debt decreases more')
        await fail('ErrNotSafe', vat.frob, i0, ME, wad(-2), wad(-4))
        debug('debt can\'t increase, even if ink increases more')
        await fail('ErrNotSafe', vat.frob, i0, ME, wad(5), wad(1))

        debug('ink can decrease if end state is safe')
        await send(vat.frob, i0, ME, wad(-1), wad(-4))
        await send(fb.push, tag, bn2b32(ray(0.4)), t1 + 1000)
        debug('debt can increase if end state is safe')
        await send(vat.frob, i0, ME, wad(5), wad(1))
      })

      it('test_alt_callers', async () => {

        await send(vat.slip, i0, ALI, wad(1))
        await send(vat.slip, i0, BOB, wad(1))
        await send(vat.slip, i0, CAT, wad(1))
        await Promise.all([ALI, BOB, CAT].map(usr => send(vat.slip, i0, usr, rad(20))))
        await send(vat.connect(ali).frob, i0, ALI, wad(10), wad(5))

        debug('anyone can lock')
        await send(vat.connect(ali).frob, i0, ALI, wad(1), wad(0))
        await send(vat.connect(bob).frob, i0, ALI, wad(1), wad(0))
        await send(vat.connect(cat).frob, i0, ALI, wad(1), wad(0))

        // but only with own gems - N/A no v or w

        debug('only the lad can free')
        await send(vat.connect(ali).frob, i0, ALI, wad(-1), wad(0))
        await fail('Vat/frob/not-allowed', vat.connect(bob).frob, i0, ALI, wad(-1), wad(0))
        await fail('Vat/frob/not-allowed', vat.connect(cat).frob, i0, ALI, wad(-1), wad(0))
        debug('the lad can free to anywhere')
        // lad can free to anywhere - N/A no v or w

        debug('only the lad can draw')
        await send(vat.connect(ali).frob, i0, ALI, wad(0), wad(1))
        await fail('Vat/frob/not-allowed', vat.connect(bob).frob, i0, ALI, wad(0), wad(1))
        await fail('Vat/frob/not-allowed', vat.connect(cat).frob, i0, ALI, wad(0), wad(1))
        // lad can draw to anywhere - N/A no v or w

        debug('suck rico')
        //await send(vat.mint, BOB, wad(1))
        //await send(vat.mint, CAT, wad(1))
        await send(vat.suck, vow.address, BOB, rad(1))
        await send(vat.suck, vow.address, CAT, rad(1))

        debug('anyone can wipe')
        await send(vat.connect(ali).frob, i0, ALI, wad(0), wad(-1))
        await send(vat.connect(bob).frob, i0, ALI, wad(0), wad(-1))
        await send(vat.connect(cat).frob, i0, ALI, wad(0), wad(-1))
        debug('but only with their own dai')
        // but only with their own dai - N/A no v or w
      })

      it('test_hope', async () => {
        await Promise.all([ALI, BOB, CAT].map(usr => send(vat.slip, i0, usr, rad(20))))

        await send(vat.connect(ali).frob, i0, ALI, wad(10), wad(5))

        debug('only owner can do risky actions')
        await send(vat.connect(ali).frob, i0, ALI, wad(0), wad(1))
        await fail('Vat/frob/not-allowed', vat.connect(bob).frob, i0, ALI, wad(0), wad(1))
        await fail('Vat/frob/not-allowed', vat.connect(cat).frob, i0, ALI, wad(0), wad(1))

        // unless they hope another user - N/A no hope
      })

      it('test_dust', async () => {
        await send(vat.frob, i0, ME, wad(9), wad(1))
        await send(vat.filk, i0, b32('dust'), rad(5))
        await fail('ErrUrnDust', vat.frob, i0, ME, wad(5), wad(2))
        await send(vat.frob, i0, ME, wad(0), wad(5))
        await fail('ErrUrnDust', vat.frob, i0, ME, wad(0), wad(-5))
        await send(vat.frob, i0, ME, wad(0), wad(-6))
      })
    })

    describe('plug', () => {
      before(async () => {
        await send(vat.ward, dock.address, true)
        await send(joy.ward, dock.address, true)
        await snapshot_name(hh)
      })
      after(async () => {
        await revert_pop(hh)
      })
      afterEach(async () => {
        await revert_name(hh)
      })

      it('test_gem_plug', async () => {
        await send(gem.mint, ME, wad(20))
        await send(gem.approve, dock.address, wad(20))
        debug('plug 10')
        await send(dock.join_gem, vat.address, i0, ME, wad(10))
        want(await vat.gem(i0, ME)).to.eql(wad(10))
        // rico has no dss cage analogue
      })


      it('test_dai_exit', async () => {
        await send(vat.suck, vow.address, ME, rad(100))
        debug('exiting...')
        await send(dock.exit_rico, vat.address, joy.address, ME, wad(40))
        want(await joy.balanceOf(ME)).to.eql(wad(40))
        want(await vat.joy(ME)).to.eql(rad(60))
        // no cage, rest is N/A
      })

      it('test_dai_exit_plug', async () => {
        await send(vat.suck, vow.address, ME, rad(100))
        debug('exiting')
        await send(dock.exit_rico, vat.address, joy.address, ME, wad(60))
        await send(joy.approve, dock.address, constants.MaxUint256)
        debug('joining')
        await send(dock.join_rico, vat.address, joy.address, ME, wad(30))
        want(await joy.balanceOf(ME)).to.eql(wad(30))
        want(await vat.joy(ME)).to.eql(rad(70))
      })

      // N/A test_cage_no_access
      //   rico has no dss cage analogue
    })

    describe('bite', () => {
      let gov, gold
      let now

      /*
      const RICO_mint = async (usr, amt : number) => {
        await send(vat.suck, usr.address, usr.address, rad(amt))
        await send(port.connect(usr).exit, vat.address, RICO.address, usr.address, wad(amt))
      }
       */

      before(async function () {

        //now = 16430421660
        //await warp(hh, now)
        debug('creating gov')
        gov = RISK // gov.mint N/A already minted RISK tokens
        await gov.mint(ME, wad(100))


        // jug N/A
        //   rico has fee, no jug
        //   dss setup doesn't actually set the fee, just creates the jug

        debug('joining gold')
        gold = gem
        await send(gold.mint, ME, wad(1000))
        await send(vat.ward, dock.address, true)
        await send(gold.approve, dock.address, constants.MaxUint256)
        await send(dock.bind_gem, vat.address, i0, gold.address)
        debug(`me gold balance = ${await gold.balanceOf(ME)}`)
        await send(dock.join_gem, vat.address, i0, ME, wad(1000))

        debug('filing')
        await send(fb.push, tag, bn2b32(ray(1)), t1 + 1000) // dss file 'spot'
        await send(vat.filk, i0, b32('line'), rad(1000))
        // cat.box N/A bail liquidates entire urn
        await send(vat.filk, i0, b32('chop'), ray(1)) // dss used wad, rico uses ray

        debug('approve gov/gold')
        await send(gold.approve, vat.address, constants.MaxUint256)
        // gov approve flap N/A not sure what to do with gov atm...

        debug('flow ramps')
        await curb_ramp(vow, gold, {'vel': constants.MaxUint256, 'rel': wad(1), 'bel': await gettime(), 'cel': 1})
        await curb_ramp(vow, RICO, {'vel': constants.MaxUint256, 'rel': wad(1), 'bel': await gettime(), 'cel': 1})
        debug(`vow ramp`)
        await curb_ramp(vow, RISK, {'vel': constants.MaxUint256, 'rel': wad(1), 'bel': await gettime(), 'cel': 1})

        await snapshot_name(hh)
      })
      after(async () => {
        await revert_pop(hh)
      })
      afterEach(async () => {
        await revert_name(hh)
      })

      it('test_set_dunk_multiple_ilks', async () => {
        // rel and vel are *sort of* like dunk and bite
        const testDunk = async (rel, vel) => {
          await send(vow.pair, gold.address, b32('rel'), rel)
          await send(vow.pair, gold.address, b32('vel'), vel)
          await send(vow.pair, gov.address, b32('rel'), rel)
          await send(vow.pair, gov.address, b32('vel'), vel)
          want((await flower.ramps(vow.address, gold.address)).rel).to.eql(rel)
          want((await flower.ramps(vow.address, gold.address)).vel).to.eql(vel)
          want((await flower.ramps(vow.address, gov.address)).rel).to.eql(rel)
          want((await flower.ramps(vow.address, gov.address)).vel).to.eql(vel)
        }
        await testDunk(wad(0), wad(0))
        await testDunk(wad(0.01), wad(0.02))
      })

      // test_cat_set_box
      //   N/A vow liquidates entire urn, no box

      // test_bite_under_dunk
      //   N/A no dunk analogue, vow can only bail entire urn

      // test_bite_over_dunk
      //   N/A no dunk analogue, vow can only bail entire urn

      // Total deficit
      const vow_Awe = async () => {
        return vat.sin(vow.address)
      }
      const vow_Joy = async () => {
        return vat.joy(vow.address)
      }
      // vow_Woe N/A - no debt queue in vow

      it('test_happy_bite', async () => {
        // set ramps high so flip flips whole gem balance
        await curb_ramp(vow, gold, {'vel': wad(1000), 'rel': wad(1000), 'bel': 0, 'cel': 1})
        // dss: spot = tag / (par . mat), tag=5, mat=2
        // rico: mark = feed.val = 2.5
        debug('create urn (push, frob)')
        await send(fb.push, tag, bn2b32(ray(2.5)), t1 + 1000) // dss file 'spot'
        await send(vat.frob, i0, ME, wad(40), wad(100))

        // tag=4, mat=2
        debug('make urn unsafe, set liquidation penalty')
        await send(fb.push, tag, bn2b32(ray(2)), t1 + 1000) // now unsafe // dss file 'spot'
        await send(vat.filk, i0, b32('chop'), ray(1.1)) // dss used wad, rico uses ray

        want(await _ink(i0, ME)).to.eql(wad(40))
        want(await _art(i0, ME)).to.eql(wad(100))
        // Woe N/A - no debt queue (Sin) in vow
        want(await vat.gem(i0, ME)).to.eql(wad(960))

        // => bite everything
        // dss checks joy 0 before tend, rico checks before bail
        want(await vat.joy(vow.address)).to.eql(rad(0))
        // cat.file dunk N/A vow always bails whole urn
        // cat.litter N/A vow always bails urn immediately
        debug('bail')
        want(await RICO.balanceOf(vow.address)).to.eql(wad(0)) // this check is not in dss
        await send(vow.bail, i0, ME)
        want(await _ink(i0, ME)).to.eql(wad(0))
        want(await _art(i0, ME)).to.eql(wad(0))
        // vow.sin(now) N/A rico vow has no debt queue

        // tend, dent, deal N/A rico flips immediately, no tend dent deal
        {
          const expected = wad(110)
          const actual: BigNumber = await RICO.balanceOf(vow.address) // need to keep to plug the joy
          const tolerance = BigNumber.from(expected).div(5)
          want(parseInt(actual.toString())).closeTo(
            parseInt(expected.toString()),
            parseInt(expected.div(5).toString())
          )
        }

        debug('keep')
        await send(vow.keep, [i0])
      })

      // test_partial_litterbox
      //   N/A bail liquidates whole urn, dart == art

      // testFail_fill_litterbox
      //   N/A bail liquidates whole urn

      // testFail_dusty_litterbox
      //   N/A bail liquidates whole urn, and there's no liquidation limit
      //   besides debt ceiling

      // test_partial_litterbox_multiple_bites
      //   N/A bail liquidates whole urn in one tx, no liquidation limit (litterbox)

      it('testFail_null_auctions_dart_realistic_values', async () => {
        debug('push + file')
        await send(vat.filk, i0, b32('dust'), rad(100))
        await send(fb.push, tag, bn2b32(ray(2.5)), t1 + 1000) // mark(spot)
        await send(vat.filk, i0, b32('line'), rad(2000))
        await send(vat.file, b32('ceil'), rad(2000 + total_pool_rico)) // dss test uses 2k, but we have debt from bpools

        // call drip with rack == 1 to update rho
        await send(vat.drip, i0)
        debug('drip (dss fold) + frob')
        let ilk = await vat.ilks(i0)
        const t0 = await gettime()
        await warp(hh, t0 + 1)
        // set fee, similar to rate in dss fold
        // use sqrt because next drip will be called two seconds after prev, so rack will be 0.25
        await send(vat.filk, i0, b32('fee'), ray(Math.sqrt(0.25)))
        await warp(hh, t0 + 2)
        debug(`tart=${ilk.tart} rack=${ilk.rack} line=${ilk.line} debt=${await vat.debt()}`)
        await send(vat.frob, i0, ME, wad(800), wad(2000))
        ilk = await vat.ilks(i0)
        debug(`tart=${ilk.tart} rack=${ilk.rack} line=${ilk.line} debt=${await vat.debt()}`)

        // overflowing box N/A rico has no liquidation limit (besides ceil/line)
        // vow has no dustiness check, just liquidates entire urn
      })

      // testFail_null_auctions_dart_artificial_values
      //   N/A no box, bail liquidates entire urn immediately

      // testFail_null_auctions_dink_artificial_values
      //   TODO might be relevant, need to update flow.  right now bill isn't even used, so rico trades all the ink
      //   with balancer.  N/A for now

      // testFail_null_auctions_dink_artificial_values_2
      //   N/A no dunk, vow always bails whole urn

      // testFail_null_spot_value
      //   N/A bail amount doesn't depend on spot, only reverts if urn is safe

      it('testFail_vault_is_safe', async () => {
        debug(`before frob vat.gem(me) = ${await vat.gem(i0, ME)}`)
        await send(fb.push, tag, bn2b32(ray(2.5)), t1 + 1000) // mark(spot)
        await send(vat.frob, i0, ME, wad(100), wad(150))

        debug(`after frob vat.gem(me) = ${await vat.gem(i0, ME)}`)
        want(await _ink(i0, ME)).to.eql(wad(100))
        want(await _art(i0, ME)).to.eql(wad(150))
        // Woe N/A - no debt queue (Sin) in vow
        want(await vat.gem(i0, ME)).to.eql(wad(900))

        // dunk, litter N/A bail liquidates whole urn in one tx, no litterbox

        debug('bail')
        await fail('ERR_SAFE', vow.bail, i0, ME)
      })

      it('test_floppy_bite', async () => {
        await send(fb.push, tag, bn2b32(ray(2.5)), t1 + 1000) // mark(spot)
        await send(vat.frob, i0, ME, wad(40), wad(100))
        await send(fb.push, tag, bn2b32(ray(2)), t1 + 1000) // mark(spot)

        // mimic dss auction rates...need to flop 1000 risk
        const riskAmt = 1000
        await curb_ramp(vow, gold, {'vel': wad(1), 'rel': wad(1), 'bel': await gettime(), 'cel': 1})
        debug('FLOP CURB')
        await curb_ramp(vow, RISK, {'vel': wad(riskAmt), 'rel': wad(1), 'bel': await gettime(), 'cel': 1})
        debug('FLOP CURB DONE')

        // dunk N/A bail always liquidates whole urn
        // vow.sin N/A no debt queue
        debug('bail')
        await send(vow.bail, i0, ME)

        // flog, vow.Sin, vow.Woe N/A no debt queue
        // Ash N/A no auction
        want(await vat.joy(vow.address)).to.eql(wad(0))

        // sump, dump N/A no auction
        // vow.flop becomes vow.keep, which calls flower.flop
        debug('keep')
        want(await gov.balanceOf(vault.address)).to.eql(wad(total_pool_risk)) // the vault is the dss 'bidder'
        flower.flow.reset()
        await send(vow.keep, [i0])
        want(flower.flow).to.have.been.called

        // Woe, Ash N/A (see above)
        console.log("total_pool_risk", total_pool_risk, "riskamt", riskAmt, "bal", (await gov.balanceOf(vault.address)).toString())
        want(await gov.balanceOf(vault.address)).to.eql(wad(total_pool_risk + riskAmt))
      })

      it('test_flappy_bite', async () => {
        // get some surplus
        debug('suck joy to vow')
        const flapAmt = 100 // change from dss: flapAmt > bar to flap
        await send(vat.suck, ME, vow.address, rad(flapAmt))
        want(await vat.joy(vow.address)).to.eql(rad(flapAmt)) // vow keep trades
        want(await gov.balanceOf(vault.address)).to.eql(wad(total_pool_risk))

        // dss bump ~ rico vel
        await curb_ramp(vow, RICO, {'vel': wad(flapAmt), 'rel': wad(1), 'bel': await gettime(), 'cel': 1})
        want(await vow_Awe()).to.eql(wad(0))
        // mimic dss auction rates...need to flap flapAmt rico
        // so vow's joy balance
        debug('keep', await vat.sin(vow.address))
        flower.flow.reset()
        await send(vow.keep, [i0])
        want(flower.flow).to.have.been.called

        debug('check balances')
        want(await vat.joy(vault.address)).to.eql(rad(0))
        want((await gov.balanceOf(vault.address)).lt(wad(total_pool_risk))).to.be.true
        want(await RICO.balanceOf(vault.address)).to.eql(wad(total_pool_rico + flapAmt))
      })
    })

    describe('fold', () => {
      before(async () => {
        await send(vat.file, b32('ceil'), rad(100))
        await send(vat.filk, i0, b32('line'), rad(100))
        await snapshot_name(hh)
      })
      after(async () => {
        await revert_pop(hh)
      })
      afterEach(async () => {
        await revert_name(hh)
      })

      const draw = async (ilk, joy) => {
        // different from dss -- need to account for balancer pool rico in ceil (dss Line)
        await send(vat.file, b32('ceil'), rad(joy + total_pool_rico))
        await send(vat.filk, ilk, b32('line'), rad(joy))
        await send(fb.push, tag, bn2b32(ray(1)), t1 + 1000) // mark(spot)

        await send(vat.slip, ilk, ME, rad(1))
        await send(vat.drip, i0) // update rho
        await send(vat.frob, ilk, ME, wad(1), wad(joy))
      }

      const tab = async (ilk, _urn) => {
        const [ink, art] = await vat.urns(ilk, _urn)
        const [tart, rack, mark, line, dust] = await vat.ilks(ilk)

        debug('tab')
        debug(`tart=${tart} art=${art} rack=${rack} tab=${art.mul(rack)}`)
        return art.mul(rack)
      }

      it('test_fold', async () => {
        want((await vat.ilks(i0)).fee).to.eql(ray(1))
        debug('draw')
        await draw(i0, 1)
        await send(vat.filk, i0, b32('fee'), ray(Math.cbrt(1.05))) // cbrt bc next drip is three seconds later
        want(await tab(i0, ME)).to.eql(rad(1))

        const t0 = await gettime()
        await warp(hh, t0 + 1)
        debug('drip')
        let mejoy0 = await vat.joy(ME)
        await send(vat.drip, i0)
        let mejoy1 = await vat.joy(ME)

        want(parseInt((await tab(i0, ME)).toString()))
          .closeTo(
            parseInt(rad(1.05).toString()),
            parseInt(rad(0.001).toString())
          )
        want(parseInt(mejoy1.sub(mejoy0).toString()))
          .closeTo(
            parseInt(rad(0.05).toString()),
            parseInt(rad(0.001).toString())
          )
      })
    })
  })

  /*
  describe('vow', () => {
    let gov
    before(async () => {
      gov = RISK

      // flapper ward vow N/A vow doesn't need to modify flower, just sends/receives stuff

      const ramp = await flower.ramps(vow.address, RICO.address)
      await send(vow.pair, RICO.address, b32('vel'), wad(100))
      await curb_ramp(vow, RICO, {vel: wad(100), rel: wad(1), bel: await gettime(), cel: 1})
      // sump, dump N/A no auction

      // me hope flower N/A flower doesn't need to modify vat, vow does
      await snapshot_name(hh)
    })
    after(async () => {
      await revert_pop(hh)
    })
    afterEach(async () => {
      await revert_name(hh)
    })

    it('test_change_flap_flop', async () => {
      want(await vow.flow()).to.eql(flower.address)

      debug('creating new flower')
      const newFlower = await flower_type.deploy();

      // newFlap/newFlop ward vow N/A vow doesn't need flower privileges, just sends/receives

      // in dss can[vow][flapper] is true
      // N/A rico doesn't have can, vow handles the vat balances

      debug('linking new flower')
      await send(vow.link, b32('flow'), newFlower.address)

      want(await vow.flow()).to.eql(newFlower.address)

      // dss can N/A, same as above
    })

    // test_flog_wait
    //   N/A no flog, no debt queue

    const suck = async (who, n) => {
      debug(`suck vow to ${who}`)
      await vat.suck(vow.address, who, rad(n))
    }
    const flog = async (n) => {
      // dss sucks to null address
      // rico keep calls rake() which
      await suck(constants.AddressZero, n)
    }

    const heal = async (n) => {
      await vow.heal(rad(n))
    }

    // test_no_reflop
    it('test_no_reflop', async () => {
      // vow.flog N/A no debt queue, rico 'flog' just sucks
      // set vel high
      assert(false, 'TODO test for flip/flap/flop in new vow')
      debug(await RISK.totalSupply())
      await curb_ramp(vow, FLOP, { vel: wad(500), rel: wad(100), bel: await gettime(), cel: 1 })
      await flog(100)
      want(await vat.joy(vow.address)).to.eql(rad(0))
      want(await vat.sin(vow.address)).to.eql(rad(100))

      debug('keep 1')
      debug(`RISK=${await RISK.totalSupply()}`)
      flower.flow.reset()
      await send(vow.keep, [])
      want(flower.flow).to.have.been.called

      debug('keep 2')
      flower.flow.reset()
      await send(vow.keep, [])
      want(flower.flow).to.not.have.been.called
    })

    // test_no_flap_nonzero_woe
    //   N/A rico has no debt queue
    // test_no_flap_pending_flop
    //   N/A rico has no debt queue, flops are never pending
    // test_no_flap_pending_heal
    //   N/A keep always starts with heal unless joy == sin == 0,
    //   in which case heal is redundant

    // test_no_flop_pending_joy
    // test_flap
    // test_no_flap_pending_sin
    // test_multiple_flop_dents
    describe('flap/flop logic', () => {
      before(async () => {
        want(await vat.joy(vow.address)).to.eql(rad(0))
        want(await vat.sin(vow.address)).to.eql(rad(0))

        // set vel high because we're not testing partial flops atm
        await curb_ramp(vow, FLOP, {vel: wad(500), rel: wad(1), bel: await gettime(), cel: 1})
        await send(vat.file, b32('ceil'), rad(ceil + 10))
        await send(vow.file, b32('bar'), rad(1))
        await snapshot_name(hh)
      })
      afterEach(async () => { await revert_name(hh) })
      after(async () => { await revert_pop(hh) })
      beforeEach(async () => {
        flower.flap.reset()
        flower.flop.reset()
      })

      // dss: joy must be 0 to flop
      // rico: joy must be <sin to flop
      const do_keep = async (joy, sin) => {
        want(await vat.joy(vow.address)).to.eql(rad(0))
        want(await vat.sin(vow.address)).to.eql(rad(0))
        await send(vat.suck, vow.address, constants.AddressZero, rad(sin))
        await send(vat.suck, constants.AddressZero, vow.address, rad(joy))
        await send(vow.keep)
      }

      it('joy == sin', async () => {
        await do_keep(1, 1)
        want(flower.flop).to.not.have.been.called
        want(flower.flap).to.not.have.been.called
      })
      it('joy > sin + bar', async () => {
        await do_keep(3, 1)
        want(flower.flop).to.not.have.been.called
        want(flower.flap).to.have.been.calledOnce
      })

      it('joy > sin && joy <= sin + bar', async () => {
        await do_keep(2, 1)
        want(flower.flop).to.not.have.been.called
        want(flower.flap).to.not.have.been.called
      })

      it('joy < sin', async () => {
        await do_keep(1, 2)
        want(flower.flop).to.have.been.calledOnce
        want(flower.flap).to.not.have.been.called
      })

      it('joy == sin == 0', async () => {
        await do_keep(0, 0)
        want(flower.flop).to.not.have.been.called
        want(flower.flap).to.not.have.been.called
      })

      // test_no_surplus_after_good_flop
      //   N/A flops go through balancer, which doesn't accept 0 amountIn (lot)
      //   TODO is it worth it to make a mock that does?

      it('test_multiple_flop_dents', async () => {
        // set vel low so vow can only flop a little bit of risk
        await curb_ramp(vow, FLOP, {vel: wad(0.1), rel: wad(1), bel: await gettime(), cel: 1})

        await do_keep(1, 2) // suck, flop
        want(flower.flop).to.have.been.calledOnce

        flower.flop.reset()
        await send(vow.keep) // try to flop again
        want(flower.flop).to.have.been.calledOnce
      })
    })
  })
     */

  describe('flip', () => {
    const initial_gem_bal = { me: 1000 }
    // TODO resolve joy vs rico variable names
    const initial_joy_bal = { ali: 200, bob: 200 }
    let gal
    before(async () => {
      // difference from dss: rico needs to exit before flipping, so doesn't make sense to have user slip
      await send(gem.mint, ME, wad(initial_gem_bal.me))
      await send(dock.join_gem, vat.address, i0, ME, wad(initial_gem_bal.me))

      await send(vat.suck, ALI, ALI, rad(initial_joy_bal.ali))
      await send(vat.suck, BOB, BOB, rad(initial_joy_bal.bob))
      await curb_ramp(vow, gem, {'vel': constants.MaxUint256, 'rel': wad(1), 'bel': await gettime(), 'cel': 1})
      gal = cat
      await snapshot_name(hh)
    })
    afterEach(async () => { await revert_name(hh) })
    after(async () => { await revert_pop(hh) })

    it('test_kick', async () => {
      // difference from dss: need to exit before flipping (like in bail)
      // difference from dss: whoever calls flow (e.g. vow) holds the intoken
      await send(dock.exit_gem, vat.address, i0, ME, wad(100))
      debug('exited')

      await send(flower.flow, gem.address, wad(100), RICO.address, constants.MaxUint256) // no grab, no bill
    })

    // testFail_tend_empty
    // test_tend
    // test_tend_later
    // test_dent
    // test_dent_same_bidder
    // test_beg
    // test_deal
    // test_tick
    //   N/A rico has no auction, immediately trades with balancer

    // test_yank_tend
    // test_yank_dent
    //   N/A rico has no auction, immediately trades with balancer, no shutdown (dss yank is for shutdown)

    // test_no_deal_after_end
    //   N/A rico currently has no end
  })

  describe('flap', () => {
    // difference from dss: flow calls flowback, so to test some cases flow must be called by vow
    const initial_joy_bal = { vow: 1000 }
    const initial_gem_bal = { vow: 1000, ali: 200, bob: 200 } // initial balance *after* before block
    before(async () => {
      await send(vat.suck, vow.address, vow.address, rad(initial_joy_bal.vow))

      await send(gem.mint, vow.address, wad(initial_gem_bal.vow))
      await send(gem.ward, flower.address, true) // ward flower, unward me ~= DSToken setOwner
      await send(gem.ward, ME, false)

      await send(gem.connect(vow.wallet).transfer, ALI, wad(200))
      await send(gem.connect(vow.wallet).transfer, BOB, wad(200))

      await snapshot_name(hh)
    })
    afterEach(async () => { await revert_name(hh) })
    after(async () => { await revert_pop(hh) })

    it('flap test_kick', async () => {
      want(await vat.joy(vow.address)).to.eql(rad(initial_joy_bal.vow))
      // difference from dss: vow and flapper should have no risk
      want(await RISK.balanceOf(vow.address)).to.eql(wad(0))
      want(await RISK.balanceOf(flower.address)).to.eql(wad(0))

      const amt = 100
      // difference from dss: need to exit before flipping (like in bail, but with port)
      await send(dock.connect(vow.wallet).exit_rico, vat.address, RICO.address, vow.address, wad(amt))
      // flap doesn't do anything with its one arg (surplus), so use vel to set flap lot (TODO cleanup when API stable)
      await curb_ramp(vow, RICO, {'vel': wad(amt), 'rel': wad(1), 'bel': await gettime(), 'cel': 1})
      debug(`flapping`)
      let vowjoy0 = await vat.joy(vow.address)
      await send(flower.connect(vow.wallet).flow, RICO.address, wad(amt), RISK.address, constants.MaxUint256) // arg is useless atm
      let vowjoy1 = await vat.joy(vow.address)

      // no joy moved
      want(vowjoy1).to.eql(vowjoy0)

      // same as dss: kicks the auction, doesn't execute
      want(await vat.joy(flower.address)).to.eql(rad(0))
      want(await RICO.balanceOf(vow.address)).to.eql(wad(0))
      // difference from dss: check that vow got the risk from the flap
      want(await RISK.balanceOf(vow.address)).to.eql(wad(0))
      want(await RISK.balanceOf(flower.address)).to.eql(wad(0))
    })

    // testFail_tend_empty
    // test_tend
    // test_tend_dent_same_bidder
    // test_beg
    // test_tick
    //   N/A rico has standing auction mechanism, immediately trades with balancer
  })

  describe('flop.t.sol', () => {
    const initial_joy_bal = { vow: 1000, ali: 200, bob: 200 }
    before(async () => {
      await send(gem.approve, flower.address, constants.MaxUint256)

      debug('initializing joy bals')
      await send(vat.suck, vow.address, vow.address,  rad(initial_joy_bal.vow))
      await send(vat.connect(vow.wallet).gift, ALI,  rad(initial_joy_bal.ali))
      await send(vat.connect(vow.wallet).gift, BOB,  rad(initial_joy_bal.bob))

      await snapshot_name(hh)
    })
    afterEach(async () => { await revert_name(hh) })
    after(async () => { await revert_pop(hh) })

    it('test_kick', async () => {
      const lot = 200
      // difference from dss: vow/flower instead of gal
      want(await vat.joy(vow.address)).to.eql(
          rad(initial_joy_bal.vow - initial_joy_bal.ali - initial_joy_bal.bob)
      )
      want(await RICO.balanceOf(vow.address)).to.eql(wad(0))
      want(await RISK.balanceOf(vow.address)).to.eql(wad(0))
      want(await gem.balanceOf(vow.address)).to.eql(wad(0))

      want(await RICO.balanceOf(flower.address)).to.eql(wad(0))
      want(await RISK.balanceOf(flower.address)).to.eql(wad(0))
      want(await gem.balanceOf(flower.address)).to.eql(wad(0))

      // TODO RISK_mint
      debug('mint risk')
      await send(RISK.mint, vow.address, wad(lot))

      // flow is similar to kick
      await curb_ramp(vow, RISK, {'vel': constants.MaxUint256, 'rel': wad(1), 'bel': await gettime(), 'cel': 1})
      let vowjoy0 = await RICO.balanceOf(vow.address)
      debug('flop')
      let aid = await flower.connect(vow.wallet).callStatic.flow(RISK.address, wad(lot), RICO.address, constants.MaxUint256)
      debug('flop static')
      await send(flower.connect(vow.wallet).flow, RISK.address, wad(lot), RICO.address, constants.MaxUint256)
      let vowjoy1 = await RICO.balanceOf(vow.address)

      // check risk moved to flow, but no further
      // same as dss, which kicks the auction but doesn't execute it
      want(await RISK.balanceOf(flower.address)).to.eql(wad(lot))
      // vow gets the RICO
      want(await RICO.balanceOf(vow.address)).to.eql(wad(0))
      want(await RICO.balanceOf(flower.address)).to.eql(wad(0))
      want(await RICO.balanceOf(ME)).to.eql(wad(0))
      want(await RISK.balanceOf(vow.address)).to.eql(wad(0))
    })

    // test_dent
    // test_dent_Ash_less_than_bid
    // test_dent_same_bidder
    // test_tick
    //   N/A rico has standing auction mechanism, immediately trades with balancer


    // test_no_deal_after_end
    //   N/A rico currently has no end

    // test_yank
    // test_yank_no_bids
    //   N/A rico has no auction, immediately trades with balancer, no shutdown (dss yank is for shutdown)
  })

  describe('clip.t.sol', () => {
    const initial_joy_bal = { me: 1000, port: 1000, ali: 1000, bob: 1000 }
    const initial_gem_bal = { me: 1000 }
    const goldPrice = 5
    const dust = 20
    //let plot, plot_type
    //let fb, fb_type
    //const tag = Buffer.from('de'.repeat(32), 'hex')
    before(async () => {
      debug('port initial joy')
      await send(vat.suck, constants.AddressZero, dock.address, rad(initial_joy_bal.port))

      debug('set vault prices')
      await send(vault.setPrice, gem.address, RICO.address, wad(goldPrice * 11/10))
      // dss Exchange is one way gold->dai (gem->rico)
      await send(vault.setPrice, RICO.address, gem.address, wad(0))
      await send(vault.setPrice, RISK.address, RICO.address, wad(0))
      await send(vault.setPrice, RICO.address, RISK.address, wad(0))

      // vault already has a bunch of rico (dai) and gem (gold)...skip transfers
      // rico (dai) already wards port (DaiJoin)

      // rico has no dog, accounts interact with vow directly

      // already have i0, no need to init ilk

      // bad form to slip without minting gem first
      debug('mint gem')
      await send(gem.mint, ME, wad(initial_gem_bal.me))
      await send(dock.join_gem, vat.address, i0, ME, wad(initial_gem_bal.me))

      debug('set liqr, build plot+fb')
      await send(vat.filk, i0, b32('liqr'), ray(0.5)) // dss mat (rico uses inverse)
      // no pip, use plot instead
      /*
      plot_type = await ethers.getContractFactory('Plot', me)
      const fb_artifacts = require('../lib/feedbase/artifacts/src/Feedbase.sol/Feedbase.json')
      fb_type = ethers.ContractFactory.fromSolidity(fb_artifacts, me)
      plot = await plot_type.deploy()
      fb = await fb_type.deploy()
      await send(vat.ward, plot.address, true)

      await send(plot.link, b32('fb'), fb.address)
      await send(plot.link, b32('vat'), vat.address)
      await send(plot.link, b32('tip'), ME)

      await send(plot.wire, i0, tag)
       */
      debug('fb push')
      await send(fb.push, tag, hexZeroPad(ray(goldPrice).toHexString(), 32), constants.MaxUint256)
      //await send(plot.poke, i0)

      debug('filing')
      await send(vat.filk, i0, b32('dust'), rad(20))
      await send(vat.filk, i0, b32('line'), rad(10000))
      await send(vat.file, b32('ceil'), rad(10000 + total_pool_rico)) // rico has balancer pools, dss doesn't

      await send(vat.filk, i0, b32('chop'), ray(1.1)) // dss uses wad, rico uses ray
      // hole, Hole N/A (similar to cat.box), no rico equivalent, rico bails entire urn

      // dss clipper <-> rico flower (flip)

      debug('frob')
      want(await vat.gem(i0, ME)).to.eql(wad(initial_gem_bal.me))
      want(await vat.joy(ME)).to.eql(rad(0))
      await send(vat.frob, i0, ME, wad(40), wad(100))
      want(await vat.gem(i0, ME)).to.eql(wad(initial_gem_bal.me - 40))
      want(await vat.joy(ME)).to.eql(rad(100))

      debug('push 4')
      await send(fb.push, tag, hexZeroPad(ray(4).toHexString(), 32), constants.MaxUint256) // dss pip.poke
      //await send(plot.poke, i0) // dss spot.poke, now unsafe

      // dss me/ali/bob hope clip N/A, rico vat wards vow

      debug('set joy for me, ali, bob')
      await send(vat.suck, constants.AddressZero, ME, rad(initial_joy_bal.me))
      await send(vat.suck, constants.AddressZero, ALI, rad(initial_joy_bal.ali))
      await send(vat.suck, constants.AddressZero, BOB, rad(initial_joy_bal.bob))

      await curb_ramp(vow, gem, {'vel': constants.MaxUint256, 'rel': wad(1), 'bel': await gettime(), 'cel': 1})
      await snapshot_name(hh)
    })
    afterEach(async () => { await revert_name(hh) })
    after(async () => { await revert_pop(hh) })

    // test_change_dog
    //   N/A rico flow has per-auction vow (dss dog)

    // test_get_chop
    //   N/A rico has no dss chop function equivalent, just uses vat.ilks

    it('clip test_kick', async () => {
      // tip, chip N/A, rico currently has no keeper reward

      // clip.kicks() N/A rico flow doesn't count flips
      // clip.sales() N/A rico flow doesn't store sale information

      want(await vat.gem(i0, ME)).to.eql(wad(initial_gem_bal.me - 40))
      want(await vat.joy(ALI)).to.eql(rad(initial_joy_bal.ali))
      let ink, art
      [ink, art] = await vat.urns(i0, ME)
      want(ink).to.eql(wad(40))
      want(art).to.eql(wad(100))

      debug('bail ali')
      await send(vow.connect(ali).bail, i0, ME) // no keeper arg

      // clip.kicks() N/A rico flow doesn't count flips
      // clip.sales() N/A rico flow doesn't store sale information

      ;[ink, art] = await vat.urns(i0, ME)

      want(ink).to.eql(wad(0))
      want(art).to.eql(wad(0))

      // Spot = $2.5
      debug('push gold price')
      await send(fb.push, tag, hexZeroPad(ray(goldPrice).toHexString(), 32), constants.MaxUint256) // dss pip.poke
      //await send(plot.poke, i0) // dss spot.poke

      await warp(hh, (await gettime()) + 100)
      debug('frob')
      await send(vat.frob, i0, ME, wad(40), wad(100))

      // Spot = $2
      debug('push 4')
      await send(fb.push, tag, hexZeroPad(ray(4).toHexString(), 32), constants.MaxUint256) // dss pip.poke
      //await send(plot.poke, i0) // dss spot.poke, now unsafe

      // clip.sales N/A

      want(await vat.gem(i0, ME)).to.eql(wad(initial_gem_bal.me - 40 * 2))

      // buf N/A rico has no standing auction
      // tip, chip N/A

      want(await vat.joy(BOB)).to.eql(rad(initial_joy_bal.bob))

      debug('bail bob')
      await send(vow.connect(bob).bail, i0, ME)

      // clip.kicks() N/A rico flow doesn't count flips
      // clip.sales() N/A rico flow doesn't store sale information

      want(await vat.gem(i0, ME)).to.eql(wad(initial_gem_bal.me - 40 * 2))
      ;[ink, art] = await vat.urns(i0, ME)
      want(ink).to.eql(wad(0))
      want(art).to.eql(wad(0))

      want(await vat.joy(BOB)).to.eql(rad(initial_joy_bal.bob)) // dss has bailer rewards, rico bark doesn't
      // TODO use fb for rewards?
      // TODO smocks?
    })

    it('testFail_kick_zero_price', async () => {
      debug('push')
      await send(fb.push, tag, hexZeroPad('0x0', 32), constants.MaxUint256) // dss pip.poke
      //await send(plot.poke, i0) // dss spot.poke

      debug('bail')
      await fail('ERR_MARK_ZERO', vow.bail, i0, ME)
    })


    // testFail_redo_zero_price
    //   N/A rico has no auction

    it('test_kick_basic', async () => {
      await send(vow.bail, i0, ME)
    })

    it('test_kick_zero_tab', async () => {
      const urn = await vat.urns(i0, ME)
      // rico doesn't have kick() or a way to specify tab in bail
      // but tab == 0 if art == 0
      await send(vat.frob, i0, ME, wad(0), wad(0).sub(urn.art)) // now safe
      want((await vat.urns(i0, ME)).art).to.eql(wad(0))
      await fail('ERR_SAFE', vow.bail, i0, ME)
    })

    it('test_kick_zero_lot', async () => {
      const urn = await vat.urns(i0, ME)
      // but cut == 0 if ink == 0
      debug('file')
      // TODO curb_ramp handle undefined?
      // vel/rel similar to dss lot
      await curb_ramp(vow, gem, {'vel': wad(0), 'rel': wad(1), 'bel': await gettime(), 'cel': 1})
      debug('bail')
      await fail('ERR_LOT_ZERO', vow.bail, i0, ME)
    })

  })
})
