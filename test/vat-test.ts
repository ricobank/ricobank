import { expect as want } from 'chai'

import * as hh from 'hardhat'
import { ethers } from 'hardhat'

import { fail, send, wad, ray, rad, N, U256_MAX, warp } from 'minihat'
import { constants } from 'ethers'

import { b32 } from './helpers'

const dpack = require('@etherpacks/dpack')
const debug = require('debug')('rico:test')

const i0 = Buffer.alloc(32) // ilk 0 id

let snaps = {}
const snapshot_name = async (name) => {
  const _snap = await hh.network.provider.request({
    method: 'evm_snapshot'
  })
  snaps[name] = _snap
}

const revert_name = async (name) => {
  await hh.network.provider.request({
    method: 'evm_revert',
    params: [snaps[name]]
  })
  await snapshot_name(name)
}

describe('Vat', () => {
  let ali, bob, cat, dan
  let ALI, BOB, CAT, DAN
  let vat; let vat_type
  let gem_type
  let plug, port, flower, vow
  let RICO, RISK, WETH
  before(async () => {
    [ali, bob, cat, dan] = await ethers.getSigners();
    [ALI, BOB, CAT, DAN] = [ali, bob, cat, dan].map(signer => signer.address)
    vat_type = await ethers.getContractFactory('MockVat', ali)
    const gem_artifacts = require('../lib/gemfab/artifacts/sol/gem.sol/Gem.json')
    gem_type = ethers.ContractFactory.fromSolidity(gem_artifacts, ali)
    const pack = await hh.run('deploy-ricobank', { mock: 'true' })
    const dapp = await dpack.load(pack, ethers)

    vat = await vat_type.deploy()
    flower = dapp.flow
    plug = dapp.plug
    port = dapp.port
    vow = dapp.vow
    RICO = dapp.rico
    RISK = dapp.risk
    WETH = dapp.weth

    await send(vat.ward, plug.address, true)
    await send(WETH.approve, plug.address, U256_MAX)

    await send(plug.bind, vat.address, i0, WETH.address, true)
    await send(port.bind, vat.address, RICO.address, true)

    await send(vat.init, i0)
    await send(vat.file, b32('ceil'), rad(1000))
    await send(vat.filk, i0, b32('line'), rad(1000))

    await send(vat.plot, i0, ray(1).toString())

    await snapshot_name('setup')
  })

  describe('non', () => {
    before(async () => {
      await send(WETH.deposit, { value: ethers.utils.parseEther('1000.0') })
      await send(plug.join, vat.address, i0, WETH.address, ALI, wad(1000))
      await send(RICO.mint, ALI, wad(1000))
      await snapshot_name('non')
    })
    after(async () => {
      await revert_name('setup')
    })
    beforeEach(async () => {
      await revert_name('non')
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

      const [, , mark0] = await vat.ilks(i0)
      want(mark0.eq(ray(1))).true

      await send(vat.plot, i0, ray(1))

      const [, , mark1] = await vat.ilks(i0)
      want(mark1.eq(ray(1))).true

      const safe2 = await vat.callStatic.safe(i0, ALI)
      want(safe2).true

      await send(vat.plot, i0, ray(1).div(5))

      const safe3 = await vat.callStatic.safe(i0, ALI)
      want(safe3).false
    })
  })

  describe('dss', () => {
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

    // dss sends some external calls from test address, separate from ali, bob, cat
    // usr is contract creator
    let me
    let ME
    before(async () => {
      [me, ali, bob, cat] = [ali, bob, cat, dan];
      [ME, ALI, BOB, CAT] = [ALI, BOB, CAT, DAN]
    })
    after(async () => {
      [ali, bob, cat, dan] = [me, ali, bob, cat];
      [ALI, BOB, CAT, DAN] = [ME, ALI, BOB, CAT]
    })

    describe('frob', () => {
      before(async () => {
        want(await vat.gem(i0, ME)).to.eql(constants.Zero) // unjoined
        want(await WETH.balanceOf(ME)).to.eql(constants.Zero)
        await send(WETH.deposit, { value: ethers.utils.parseEther('1000.0') })
        await send(plug.join, vat.address, i0, WETH.address, ME, wad(1000))
        await send(vat.plot, i0, ray(1)) // dss file 'spot'
        await send(vat.filk, i0, b32('line'), rad(1000))
        await snapshot_name('dss/frob')
      })
      after(async () => {
        await revert_name('setup')
      })
      beforeEach(async () => {
        await revert_name('dss/frob')
      })

      it('test_setup', async () => {
        want(await WETH.balanceOf(plug.address)).to.eql(wad(1000))
        want(await vat.gem(i0, ME)).to.eql(wad(1000))
      })

      it('test_join', async () => {
        // urn  == (ALI, ilk)
        // gold == gem
        // i0 ~ 'gold'
        await send(WETH.deposit, { value: ethers.utils.parseEther('500.0') })
        want(await WETH.balanceOf(ME)).to.eql(wad(500))
        want(await WETH.balanceOf(plug.address)).to.eql(wad(1000))
        await send(plug.join, vat.address, i0, WETH.address, ME, wad(500))
        want(await WETH.balanceOf(ME)).to.eql(wad(0))
        want(await WETH.balanceOf(plug.address)).to.eql(wad(1500))
        await send(plug.exit, vat.address, i0, WETH.address, ME, wad(250))
        want(await WETH.balanceOf(ME)).to.eql(wad(250))
        want(await WETH.balanceOf(plug.address)).to.eql(wad(1250))
      })

      it('test_lock', async () => {
        want(await _ink(i0, ME)).to.eql(constants.Zero)
        want(await vat.gem(i0, ME)).to.eql(wad(1000))
        await send(vat.frob, i0, ME, ME, ME, wad(6), wad(0))
        want(await _ink(i0, ME)).to.eql(wad(6))
        want(await vat.gem(i0, ME)).to.eql(wad(994))
        await send(vat.frob, i0, ME, ME, ME, wad(-6), wad(0))
        want(await _ink(i0, ME)).to.eql(constants.Zero)
        want(await vat.gem(i0, ME)).to.eql(wad(1000))
      })

      it('test_calm', async () => {
        // calm means that the debt ceiling is not exceeded
        // it's ok to increase debt as long as you remain calm
        await send(vat.filk, i0, b32('line'), rad(10)) // filk ~ dss file
        await send(vat.frob, i0, ME, ME, ME, wad(10), wad(9))
        debug('only if under debt ceiling')
        await fail('Vat/ceiling-exceeded', vat.frob, i0, ME, ME, ME, wad(0), wad(2))
      })

      it('test_cool', async () => {
        // cool means that the debt has decreased
        // it's ok to be over the debt ceiling as long as you're cool
        await send(vat.filk, i0, b32('line'), rad(10))
        await send(vat.frob, i0, ME, ME, ME, wad(10), wad(8))
        await send(vat.filk, i0, b32('line'), rad(5))
        debug('can decrease debt when over ceiling')
        await send(vat.frob, i0, ME, ME, ME, wad(0), wad(-1))
      })

      it('test_safe', async () => {
        // safe means that the cdp is not risky
        // you can't frob a cdp into unsafe
        await send(vat.frob, i0, ME, ME, ME, wad(10), wad(5))
        await fail('Vat/not-safe', vat.frob, i0, ME, ME, ME, wad(0), wad(6))
      })

      it('test_nice', async () => {
        // nice means that the collateral has increased or the debt has
        // decreased. remaining unsafe is ok as long as you're nice

        await send(vat.frob, i0, ME, ME, ME, wad(10), wad(10))
        await send(vat.plot, i0, ray(0.5))
        debug('debt can\'t increase if unsafe')
        await fail('Vat/not-safe', vat.frob, i0, ME, ME, ME, wad(0), wad(1))
        debug('debt can decrease')
        await send(vat.frob, i0, ME, ME, ME, wad(0), wad(-1))
        debug('ink can\'t decrease')
        await fail('Vat/not-safe', vat.frob, i0, ME, ME, ME, wad(-1), wad(0))
        debug('ink can increase')
        await send(vat.frob, i0, ME, ME, ME, wad(1), wad(0))

        debug('cdp is still unsafe')
        debug('ink can\'t decrease, even if debt decreases more')
        await fail('Vat/not-safe', vat.frob, i0, ME, ME, ME, wad(-2), wad(-4))
        debug('debt can\'t increase, even if ink increases more')
        await fail('Vat/not-safe', vat.frob, i0, ME, ME, ME, wad(5), wad(1))

        debug('ink can decrease if end state is safe')
        await send(vat.frob, i0, ME, ME, ME, wad(-1), wad(-4))
        await send(vat.plot, i0, ray(0.4))
        debug('debt can increase if end state is safe')
        await send(vat.frob, i0, ME, ME, ME, wad(5), wad(1))
      })

      it('test_alt_callers', async () => {

        await Promise.all([ALI, BOB, CAT].map(usr => send(vat.slip, i0, usr, rad(20))))
        await send(vat.connect(ali).frob, i0, ALI, ALI, ALI, wad(10), wad(5))

        debug('anyone can lock')
        await send(vat.connect(ali).frob, i0, ALI, ALI, ALI, wad(1), wad(0))
        await send(vat.connect(bob).frob, i0, ALI, BOB, BOB, wad(1), wad(0))
        await send(vat.connect(cat).frob, i0, ALI, CAT, CAT, wad(1), wad(0))

        debug('but only with their own gems')
        await fail('Vat/frob/not-allowed', vat.connect(ali).frob, i0, ALI, BOB, ALI, wad(1), wad(0))
        await fail('Vat/frob/not-allowed', vat.connect(bob).frob, i0, ALI, CAT, BOB, wad(1), wad(0))
        await fail('Vat/frob/not-allowed', vat.connect(cat).frob, i0, ALI, ALI, CAT, wad(1), wad(0))

        debug('only the lad can free')
        await send(vat.connect(ali).frob, i0, ALI, ALI, ALI, wad(-1), wad(0))
        await fail('Vat/frob/not-allowed', vat.connect(bob).frob, i0, ALI, BOB, BOB, wad(-1), wad(0))
        await fail('Vat/frob/not-allowed', vat.connect(cat).frob, i0, ALI, CAT, CAT, wad(-1), wad(0))
        debug('the lad can free to anywhere')
        await send(vat.connect(ali).frob, i0, ALI, BOB, ALI, wad(-1), wad(0))
        await send(vat.connect(ali).frob, i0, ALI, CAT, ALI, wad(-1), wad(0))

        debug('only the lad can draw')
        await send(vat.connect(ali).frob, i0, ALI, ALI, ALI, wad(0), wad(1))
        await fail('Vat/frob/not-allowed', vat.connect(bob).frob, i0, ALI, BOB, BOB, wad(0), wad(1))
        await fail('Vat/frob/not-allowed', vat.connect(cat).frob, i0, ALI, CAT, CAT, wad(0), wad(1))
        debug('the lad can draw to anywhere')
        await send(vat.connect(ali).frob, i0, ALI, ALI, BOB, wad(0), wad(1))
        await send(vat.connect(ali).frob, i0, ALI, ALI, CAT, wad(0), wad(1))

        await send(vat.mint, BOB, wad(1))
        await send(vat.mint, CAT, wad(1))

        debug('anyone can wipe')
        await send(vat.connect(ali).frob, i0, ALI, ALI, ALI, wad(0), wad(-1))
        await send(vat.connect(bob).frob, i0, ALI, BOB, BOB, wad(0), wad(-1))
        await send(vat.connect(cat).frob, i0, ALI, CAT, CAT, wad(0), wad(-1))
        debug('but only with their own rico')
        await fail('Vat/frob/not-allowed', vat.connect(ali).frob, i0, ALI, ALI, BOB, wad(0), wad(-1))
        await fail('Vat/frob/not-allowed', vat.connect(bob).frob, i0, ALI, BOB, CAT, wad(0), wad(-1))
        await fail('Vat/frob/not-allowed', vat.connect(cat).frob, i0, ALI, CAT, ALI, wad(0), wad(-1))
      })

      it('test_trust', async () => {
        await Promise.all([ALI, BOB, CAT].map(usr => send(vat.slip, i0, usr, rad(20))))

        await send(vat.connect(ali).frob, i0, ALI, ALI, ALI, wad(10), wad(5))

        debug('only owner can do risky actions')
        await send(vat.connect(ali).frob, i0, ALI, ALI, ALI, wad(0), wad(1))
        await fail('Vat/frob/not-allowed', vat.connect(bob).frob, i0, ALI, BOB, BOB, wad(0), wad(1))
        await fail('Vat/frob/not-allowed', vat.connect(cat).frob, i0, ALI, CAT, CAT, wad(0), wad(1))

        await send(vat.connect(ali).trust, BOB, true)

        debug('unless they trust another user')
        await send(vat.connect(ali).frob, i0, ALI, ALI, ALI, wad(0), wad(1))
        await send(vat.connect(bob).frob, i0, ALI, BOB, BOB, wad(0), wad(1))
        await fail('Vat/frob/not-allowed', vat.connect(cat).frob, i0, ALI, CAT, CAT, wad(0), wad(1))
      })

      it('test_dust', async () => {
        await send(vat.frob, i0, ME, ME, ME, wad(9), wad(1))
        await send(vat.filk, i0, b32('dust'), rad(5))
        await fail('Vat/dust', vat.frob, i0, ME, ME, ME, wad(5), wad(2))
        await send(vat.frob, i0, ME, ME, ME, wad(0), wad(5))
        await fail('Vat/dust', vat.frob, i0, ME, ME, ME, wad(0), wad(-5))
        await send(vat.frob, i0, ME, ME, ME, wad(0), wad(-6))
      })
    })

    describe('join', () => {
      before(async () => {
        await snapshot_name('dss/join')
      })
      after(async () => {
        await revert_name('setup')
      })
      beforeEach(async () => {
        await revert_name('dss/join')
      })

      it('test_gem_join', async () => {
        await send(WETH.deposit, { value: ethers.utils.parseEther('20.0') })
        await send(WETH.approve, plug.address, wad(20))
        debug('join 10')
        await send(plug.join, vat.address, i0, WETH.address, ME, wad(10))
        want(await vat.gem(i0, ME)).to.eql(wad(10))
        // rico has no dss cage analogue
      })


      it('test_rico_exit', async () => {
        await send(vat.mint, ME, rad(100))
        await send(vat.trust, port.address, true)
        debug('exiting...')
        await send(port.exit, vat.address, RICO.address, ME, wad(40))
        want(await RICO.balanceOf(ME)).to.eql(wad(40))
        want(await vat.joy(ME)).to.eql(rad(60))
        // no cage, rest is N/A
      })

      it('test_rico_exit_join', async () => {
        await send(vat.mint, ME, rad(100))
        await send(vat.trust, port.address, true)
        debug('exiting')
        await send(port.exit, vat.address, RICO.address, ME, wad(60))
        await send(RICO.approve, port.address, constants.MaxUint256)
        debug('joining')
        await send(port.join, vat.address, RICO.address, ME, wad(30))
        want(await RICO.balanceOf(ME)).to.eql(wad(30))
        want(await vat.joy(ME)).to.eql(rad(70))
      })

      // N/A test_cage_no_access
      //   rico has no dss cage analogue
    })

    describe('bite', () => {
      let gold
      before(async () => {
        await warp(hh, 16430421660)
        debug('creating gold')

        debug('minting RISK tokens')
        await send(RISK.mint, ME, wad(100))
        await send(flower.ward, vow.address, true)

        // jug N/A
        //   rico doesn't have stability fees, it just manipulates price

        debug('creating and joining gold')
        gold = await gem_type.deploy('gold', 'GOLD')
        await send(gold.mint, ME, wad(1000))
        await send(gold.approve, plug.address, constants.MaxUint256)
        await send(plug.bind, vat.address, i0, gold.address, true)
        debug(`my balance = ${await gold.balanceOf(ME)}`)
        await send(plug.join, vat.address, i0, gold.address, ME, wad(1000))

        debug('filing')
        await send(vat.plot, i0, ray(1)) // dss file 'spot'
        await send(vat.filk, i0, b32('line'), rad(1000))
        // box [rad] -> flower.ramps[joy].vel [wad]
        // max rico up for auction -> max joy being traded
        // rico has no cat, so box stuff is moved to flow (aka flip/flap/flop)
        debug('setting vel (FKA box)')
        await send(flower.filem, RICO.address, b32('vel'), wad(10000000))
        await send(flower.ward, vow.address, true)
        await send(vow.ward, flower.address, true)
        await send(vow.lilk, i0, b32('flipper'), flower.address)
        await send(vat.filk, i0, b32('chop'), ray(1)) // dss used wad, rico uses ray

        debug('vat ward/trust vow, approve RISK/gold')
        await send(vat.trust, vow.address, true)
        await send(gold.approve, vat.address, constants.MaxUint256)
        // RISK approve flap N/A not sure what to do with RISK atm...

        await snapshot_name('dss/bite')
      })
      after(async () => {
        await revert_name('setup')
      })
      beforeEach(async () => {
        await revert_name('dss/bite')
      })

      it('test_set_dunk_multiple_ilks', async () => {
        // rel and vel are *sort of* like dunk and bite
        want((await flower.ramps(gold.address)).rel).to.eql(wad(0))
        want((await flower.ramps(gold.address)).vel).to.eql(wad(0))
        want((await flower.ramps(RISK.address)).rel).to.eql(wad(0))
        want((await flower.ramps(RISK.address)).vel).to.eql(wad(0))
        await send(flower.filem, gold.address, b32('rel'), wad(0.01))
        await send(flower.filem, gold.address, b32('vel'), wad(0.02))
        want((await flower.ramps(gold.address)).rel).to.eql(wad(0.01))
        want((await flower.ramps(gold.address)).vel).to.eql(wad(0.02))
        await send(flower.filem, RISK.address, b32('rel'), wad(0.01))
        await send(flower.filem, RISK.address, b32('vel'), wad(0.02))
        want((await flower.ramps(RISK.address)).rel).to.eql(wad(0.01))
        want((await flower.ramps(RISK.address)).vel).to.eql(wad(0.02))
      })

      it('test_cat_set_box', async () => {
        // rico analogue of box is flower.ramps[RICO].vel
        want((await flower.ramps(RICO.address)).vel).to.eql(wad(10000000))
        await send(flower.filem, RICO.address, b32('vel'), wad(20000000))
        want((await flower.ramps(RICO.address)).vel).to.eql(wad(20000000))
      })

      // test_bite_under_dunk
      //   N/A no dunk analogue, vow can only bail entire urn

      // test_bite_over_dunk
      //   N/A no dunk analogue, vow can only bail entire urn

      // test_happy_bite

    })
  })
})
