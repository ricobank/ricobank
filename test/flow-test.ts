import { expect as want } from 'chai'

import * as hh from 'hardhat'
import { ethers } from 'hardhat'

const dpack = require('@etherpacks/dpack')

import { b32, revert, snapshot, filem_ramp } from './helpers'
import { mine, send, U256_MAX, wad } from 'minihat'

describe('RicoFlowerV1 balancer interaction', () => {
  let ali, bob, cat
  let ALI, BOB, CAT
  let RICO, RISK, WETH
  let flower
  let vault
  let poolId_weth_rico
  let poolId_risk_rico
  before(async () => {
    [ali, bob, cat] = await ethers.getSigners();
    [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address)

    const pack = await hh.run('deploy-ricobank', { mock: 'true' })
    const dapp = await dpack.load(pack, ethers)

    flower = dapp.ricoflowerv1
    vault = dapp.vault
    RICO = dapp.rico
    RISK = dapp.risk
    WETH = dapp.weth

    await send(WETH.deposit, {value: ethers.utils.parseEther("2100.0")})
    await send(RICO.mint, ALI, wad(10000))
    await send(RISK.mint, ALI, wad(10000))

    await send(WETH.approve, vault.address, U256_MAX)
    await send(RICO.approve, vault.address, U256_MAX)
    await send(RISK.approve, vault.address, U256_MAX)

    const weth_rico_tokens = [{token: WETH, weight: wad(0.5), amountIn: wad(2000)},
                              {token: RICO, weight: wad(0.5), amountIn: wad(2000)}]
    const risk_rico_tokens = [{token: RISK, weight: wad(0.5), amountIn: wad(2000)},
                              {token: RICO, weight: wad(0.5), amountIn: wad(2000)}]

    const weth_rico_args = {
      balancer_pack: pack,
      token_settings: weth_rico_tokens,
      name: 'mock',
      symbol: 'MOCK',
      swapFeePercentage: wad(0.01)
    }
    const risk_rico_args = {
      balancer_pack: pack,
      token_settings: risk_rico_tokens,
      name: 'mock',
      symbol: 'MOCK',
      swapFeePercentage: wad(0.01)
    }
    poolId_weth_rico = (await hh.run('build-weighted-bpool', weth_rico_args)).pool_id
    poolId_risk_rico = (await hh.run('build-weighted-bpool', risk_rico_args)).pool_id

    await filem_ramp(WETH, flower, {'vel': wad(1), 'rel': wad(0.001), 'bel': 0, 'cel': 600})
    await filem_ramp(RICO, flower, {'vel': wad(1), 'rel': wad(0.001), 'bel': 0, 'cel': 600})
    await send(flower.link, b32('rico'), RICO.address)
    await send(flower.link, b32('risk'), RISK.address)
    await send(flower.setVault, vault.address)
    await send(flower.setPool, WETH.address, RICO.address, poolId_weth_rico)
    await send(flower.setPool, RICO.address, RISK.address, poolId_risk_rico)
    await send(flower.setPool, RISK.address, RICO.address, poolId_risk_rico)
    await send(flower.reapprove)
    await send(flower.approve_gem, WETH.address)

    await snapshot(hh)
  })
  beforeEach(async () => {
    await revert(hh)
  })

  describe('rate limiting', () => {
    describe('flap', () => {
      it('absolute rate', async () => {
        await filem_ramp(RICO, flower, {'vel': wad(0.1), 'rel': wad(1000), 'bel': 0, 'cel': 1000})
        await send(RICO.transfer, flower.address, wad(50))
        const rico_liq_0 = await vault.getPoolTokens(poolId_risk_rico)
        // consume half the allowance
        await send(flower.flap, 0)
        const rico_liq_1 = await vault.getPoolTokens(poolId_risk_rico)
        // recharge by a quarter of capacity so should sell 75%
        await send(RICO.transfer, flower.address, wad(100))
        await mine(hh, 250)
        await send(flower.flap, 0)
        const rico_liq_2 = await vault.getPoolTokens(poolId_risk_rico)

        const sale_0 = rico_liq_1[1][1] - rico_liq_0[1][1]
        const sale_1 = rico_liq_2[1][1] - rico_liq_1[1][1]
        want(sale_0).closeTo(parseInt(wad(50).toString()), parseInt(wad(0.5).toString()))
        want(sale_1).closeTo(parseInt(wad(75).toString()), parseInt(wad(0.5).toString()))
      })
      it('relative rate', async () => {
        await filem_ramp(RICO, flower, {'vel': wad(10000), 'rel': wad(0.00001), 'bel': 0, 'cel': 1000})
        await send(RICO.transfer, flower.address, wad(50))
        const rico_liq_0 = await vault.getPoolTokens(poolId_risk_rico)
        // consume half the allowance
        await send(flower.flap, 0)
        const rico_liq_1 = await vault.getPoolTokens(poolId_risk_rico)
        // recharge by a quarter of capacity and give excess funds
        await send(RICO.transfer, flower.address, wad(100))
        await mine(hh, 250)
        await send(flower.flap, 0)
        const rico_liq_2 = await vault.getPoolTokens(poolId_risk_rico)

        const sale_0 = rico_liq_1[1][1] - rico_liq_0[1][1]
        const sale_1 = rico_liq_2[1][1] - rico_liq_1[1][1]
        want(sale_0).closeTo(parseInt(wad(50).toString()), parseInt(wad(0.5).toString()))
        want(sale_1).closeTo(parseInt(wad(75).toString()), parseInt(wad(0.5).toString()))
      })
    })
  })
})
