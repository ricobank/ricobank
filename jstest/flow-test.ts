import { expect as want } from 'chai'

import * as hh from 'hardhat'
// @ts-ignore
import { ethers } from 'hardhat'

import { smock } from '@defi-wonderland/smock'
const debug = require('debug')('rico:test')

const dpack = require('@etherpacks/dpack')

import {revert, snapshot, curb_ramp, b32} from './helpers'
import { mine, send, U256_MAX, wad } from 'minihat'

describe('flow balancer interaction', () => {
  let ali, bob, cat
  let ALI, BOB, CAT
  let RICO, RISK
  let flower
  let vault
  let vow
  let poolId_risk_rico

  const address_index = 0
  const balances_index = 1
  let rico_index

  before(async () => {
    [ali, bob, cat] = await ethers.getSigners();
    [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address)

    const pack = await hh.run('deploy-ricobank', { mock: 'true' })
    const dapp = await dpack.load(pack, ethers, ali)

    flower = dapp.flow
    vault = dapp.vault
    //vow = dapp.vow
    debug('smock')
    vow = await (await smock.mock('Vow')).deploy()
    await ali.sendTransaction({to: vow.address, value: ethers.utils.parseEther('1.0')})
    debug(`vow at ${vow.address}`)
    RICO = dapp.rico
    RISK = dapp.risk

    debug('vow link ward approve gems')
    await send(vow.link, b32('flow'), flower.address)
    await send(vow.ward, flower.address, true)
    await send(vow.reapprove_gem, RICO.address)
    await send(vow.reapprove_gem, RISK.address)

    debug('vow link ward deposit/mint coins')
    await send(RICO.mint, ALI, wad(10000))
    await send(RISK.mint, ALI, wad(10000))

    await send(RICO.approve, vault.address, U256_MAX)
    await send(RISK.approve, vault.address, U256_MAX)

    const risk_rico_tokens = [{token: RISK, weight: wad(0.5), amountIn: wad(2000)},
                              {token: RICO, weight: wad(0.5), amountIn: wad(2000)}]

    debug('build bpool')
    const risk_rico_args = {
      balancer_pack: pack,
      token_settings: risk_rico_tokens,
      name: 'mock',
      symbol: 'MOCK',
      swapFeePercentage: wad(0.01)
    }
    poolId_risk_rico = (await hh.run('build-weighted-bpool', risk_rico_args)).pool_id

    debug('ramps')
    await curb_ramp(vow, RICO, {'vel': wad(1), 'rel': wad(0.001), 'bel': 0, 'cel': 600, del: 0})
    debug('set flower vaults and pools', vault.address)
    await send(flower.setVault, vault.address)
    await send(flower.setPool, RICO.address, RISK.address, poolId_risk_rico)
    await send(flower.setPool, RISK.address, RICO.address, poolId_risk_rico)
    await send(flower.approve_gem, RICO.address)
    await send(flower.approve_gem, RISK.address)
    debug('init done')

    await snapshot(hh)
  })
  beforeEach(async () => {
    await revert(hh)
  })

  describe('rate limiting', () => {

    before(async () => {
      const tokens = await vault.getPoolTokens(poolId_risk_rico)
      rico_index = tokens[address_index][0] == RICO.address ? 0 : 1
    })

    describe('flap', () => {
      it('absolute rate', async () => {
        await curb_ramp(vow, RICO, {'vel': wad(0.1), 'rel': wad(1000), 'bel': 0, 'cel': 1000, del: 0})
        debug('rico->vow')
        await send(RICO.transfer, vow.address, wad(50))
        const rico_liq_0 = await vault.getPoolTokens(poolId_risk_rico)
        // consume half the allowance
        //await send(flower.flap, vow.address, RICO.address, RISK.address, wad(50))
        debug('vow calls flow')
        let aid = await flower.connect(vow.wallet).callStatic.flow(RICO.address, wad(50), RISK.address, U256_MAX)
        await send(flower.connect(vow.wallet).flow, RICO.address, wad(50), RISK.address, U256_MAX)
        debug('glug', aid)
        await send(flower.connect(vow.wallet).glug, aid)

        const rico_liq_1 = await vault.getPoolTokens(poolId_risk_rico)
        // recharge by a quarter of capacity so should sell 75%
        await send(RICO.transfer, vow.address, wad(100))
        await mine(hh, 250)

        //await send(flower.flap, vow.address, RICO.address, RISK.address, wad(100))
        debug('vow calls flow')
        aid = await flower.connect(vow.wallet).callStatic.flow(RICO.address, wad(100), RISK.address, U256_MAX)
        await send(flower.connect(vow.wallet).flow, RICO.address, wad(100), RISK.address, U256_MAX)
        debug('glug', aid)
        await send(flower.connect(vow.wallet).glug, aid)

        const rico_liq_2 = await vault.getPoolTokens(poolId_risk_rico)

        const sale_0 = rico_liq_1[balances_index][rico_index] - rico_liq_0[balances_index][rico_index]
        const sale_1 = rico_liq_2[balances_index][rico_index] - rico_liq_1[balances_index][rico_index]
        want(sale_0).closeTo(parseInt(wad(50).toString()), parseInt(wad(0.5).toString()))
        want(sale_1).closeTo(parseInt(wad(75).toString()), parseInt(wad(0.6).toString()))
      })
      it('relative rate', async () => {
        await curb_ramp(vow, RICO, {'vel': wad(10000), 'rel': wad(0.00001), 'bel': 0, 'cel': 1000, del: 0})
        debug('rico->vow')
        await send(RICO.transfer, vow.address, wad(50))

        const rico_liq_0 = await vault.getPoolTokens(poolId_risk_rico)
        // consume half the allowance
        //await send(flower.flap, vow.address, RICO.address, RISK.address, wad(50))
        debug('vow calls flow')
        let aid = await flower.connect(vow.wallet).callStatic.flow(RICO.address, wad(50), RISK.address, U256_MAX)
        await send(flower.connect(vow.wallet).flow, RICO.address, wad(50), RISK.address, U256_MAX)
        debug('glug', aid)
        await send(flower.connect(vow.wallet).glug, aid)

        const rico_liq_1 = await vault.getPoolTokens(poolId_risk_rico)

        // recharge by a quarter of capacity and give excess funds
        await send(RICO.transfer, vow.address, wad(100))
        await mine(hh, 250)

        //await send(flower.flap, vow.address, RICO.address, RISK.address, wad(100))
        debug('vow calls flow')
        aid = await flower.connect(vow.wallet).callStatic.flow(RICO.address, wad(100), RISK.address, U256_MAX)
        await send(flower.connect(vow.wallet).flow, RICO.address, wad(100), RISK.address, U256_MAX)
        debug('glug', aid)
        await send(flower.connect(vow.wallet).glug, aid)

        const rico_liq_2 = await vault.getPoolTokens(poolId_risk_rico)


        const sale_0 = rico_liq_1[balances_index][rico_index] - rico_liq_0[balances_index][rico_index]
        const sale_1 = rico_liq_2[balances_index][rico_index] - rico_liq_1[balances_index][rico_index]
        want(sale_0).closeTo(parseInt(wad(50).toString()), parseInt(wad(0.5).toString()))
        want(sale_1).closeTo(parseInt(wad(75).toString()), parseInt(wad(0.6).toString()))
      })
    })
  })
})
