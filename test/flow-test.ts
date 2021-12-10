import { expect as want } from 'chai'

import * as hh from 'hardhat'
import { ethers } from 'hardhat'

import { b32, snapshot, revert } from './helpers'
import { mine, wad, send, U256_MAX } from 'minihat'
const debug = require('debug')('rico:test')
const balancer = require('@balancer-labs/v2-deployments')

describe('RicoFlowerV1 balancer interaction', () => {
  let ali, bob, cat
  let ALI, BOB, CAT
  let RICO, RISK, WETH; let gem_type
  let flower; let flower_type;
  let vault; let vault_type
  let poolfab; let poolfab_type
  let pool; let pool_type
  let poolId_weth_rico
  let poolId_risk_rico
  before(async () => {
    [ali, bob, cat] = await ethers.getSigners();
    [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address)
    const gem_artifacts = require('../lib/gemfab/artifacts/sol/gem.sol/Gem.json')
    gem_type = ethers.ContractFactory.fromSolidity(gem_artifacts, ali)
    flower_type = await ethers.getContractFactory('RicoFlowerV1', ali)

    const vault_abi = await balancer.getBalancerContractAbi('20210418-vault', 'Vault')
    const vault_code = await balancer.getBalancerContractBytecode('20210418-vault', 'Vault')
    const pool_abi = await balancer.getBalancerContractAbi('20210418-weighted-pool', 'WeightedPool')
    const pool_code = await balancer.getBalancerContractBytecode('20210418-weighted-pool', 'WeightedPool')
    const poolfab_abi = await balancer.getBalancerContractAbi('20210418-weighted-pool', 'WeightedPoolFactory')
    const poolfab_code = await balancer.getBalancerContractBytecode('20210418-weighted-pool', 'WeightedPoolFactory')
    vault_type = new ethers.ContractFactory(vault_abi, vault_code, ali)
    poolfab_type = new ethers.ContractFactory(poolfab_abi, poolfab_code, ali)
    pool_type = new ethers.ContractFactory(pool_abi, pool_code, ali)

    flower = await flower_type.deploy();
    RICO = await gem_type.deploy('Rico', 'RICO')
    RISK = await gem_type.deploy('Rico Riskshare', 'RISK')
    WETH = await gem_type.deploy('Wrapped Ether', 'WETH')
    vault = await vault_type.deploy(ALI, WETH.address, 1000, 1000)
    poolfab = await poolfab_type.deploy(vault.address)

    await send(WETH.mint, ALI, wad(10000))
    await send(RICO.mint, ALI, wad(10000))
    await send(RISK.mint, ALI, wad(10000))
    await send(WETH.approve, vault.address, U256_MAX)
    await send(RICO.approve, vault.address, U256_MAX)
    await send(RISK.approve, vault.address, U256_MAX)

    // create and add liquidity to weth-rico balancer pool
    let tokens = [WETH.address, RICO.address]
    if (RICO.address < WETH.address) {
      tokens = [RICO.address, WETH.address]
    }
    let tx_create = await poolfab.create(
        'mock', 'MOCK',
        tokens,
        [wad(0.5), wad(0.5)],
        wad(0.01),
        ALI
    )
    let res = await tx_create.wait()
    let event = res.events[res.events.length - 1]
    let pool_addr = event.args.pool
    pool = pool_type.attach(pool_addr)
    poolId_weth_rico = await pool.getPoolId()
    let JOIN_KIND_INIT = 0
    let initUserData = ethers.utils.defaultAbiCoder.encode(
        ['uint256', 'uint256[]'], [JOIN_KIND_INIT, [wad(2000), wad(2000)]]
    )
    let joinPoolRequest = {
      assets: tokens,
      maxAmountsIn: [wad(2000), wad(2000)],
      userData: initUserData,
      fromInternalBalance: false
    }
    let tx = await vault.joinPool(poolId_weth_rico, ALI, ALI, joinPoolRequest)
    await tx.wait()

    // create and add liquidity to risk-rico balancer pool
    tokens = [RICO.address, RISK.address]
    if (RISK.address < RICO.address) {
      tokens = [RISK.address, RICO.address]
    }
    tx_create = await poolfab.create(
        'mock', 'MOCK',
        tokens,
        [wad(0.5), wad(0.5)],
        wad(0.01),
        ALI
    )
    res = await tx_create.wait()
    event = res.events[res.events.length - 1]
    pool_addr = event.args.pool
    pool = pool_type.attach(pool_addr)
    poolId_risk_rico = await pool.getPoolId()
    JOIN_KIND_INIT = 0
    initUserData = ethers.utils.defaultAbiCoder.encode(
        ['uint256', 'uint256[]'], [JOIN_KIND_INIT, [wad(1000), wad(1000)]]
    )
    joinPoolRequest = {
      assets: tokens,
      maxAmountsIn: [wad(1000), wad(1000)],
      userData: initUserData,
      fromInternalBalance: false
    }
    tx = await vault.joinPool(poolId_risk_rico, ALI, ALI, joinPoolRequest)
    await tx.wait()

    await send(flower.file_ramp, WETH.address, {vel:wad(1), rel:wad(0.001), bel:0, cel:600})
    await send(flower.file_ramp, RICO.address, {vel:wad(1), rel:wad(0.001), bel:0, cel:600})
    await send(flower.file, b32('rico'), RICO.address)
    await send(flower.file, b32('risk'), RISK.address)
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
        await send(flower.file_ramp, RICO.address, {vel:wad(0.1), rel:wad(1000), bel:0, cel:1000})
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
        await send(flower.file_ramp, RICO.address, {vel:wad(10000), rel:wad(0.00001), bel:0, cel:1000})
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
