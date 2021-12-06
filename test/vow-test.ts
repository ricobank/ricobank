import { expect as want } from 'chai'

import * as hh from 'hardhat'
import { ethers } from 'hardhat'
import { smock } from '@defi-wonderland/smock'

const chai = require('chai');
chai.use(smock.matchers);

import { b32, snapshot, revert } from './helpers'
import { fail, mine, wad, ray, rad, apy, send, BANKYEAR, U256_MAX } from 'minihat'
const debug = require('debug')('rico:test')
const balancer = require('@balancer-labs/v2-deployments')
const i0 = Buffer.alloc(32) // ilk 0 id

describe('vow / liq liquidation lifecycle', () => {
  let ali, bob, cat
  let ALI, BOB, CAT
  let RICO, RISK, WETH; let gem_type
  let vat; let vat_type
  let plug_join; let plug_join_type
  let vow; let vow_type
  let flower; let flower_type;
  let vault; let vault_type
  let poolfab; let poolfab_type
  let pool; let pool_type
  let weth_rico_poolId
  before(async () => {
    [ali, bob, cat] = await ethers.getSigners();
    [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address)
    const gem_artifacts = require('../lib/gemfab/artifacts/sol/gem.sol/Gem.json')
    gem_type = ethers.ContractFactory.fromSolidity(gem_artifacts, ali)
    vat_type = await smock.mock('Vat', ali)
    vow_type = await ethers.getContractFactory('Vow', ali)
    plug_join_type = await ethers.getContractFactory('Vault', ali)
    flower_type = await smock.mock('RicoFlowerV1')

    const vault_abi = await balancer.getBalancerContractAbi('20210418-vault', 'Vault')
    const vault_code = await balancer.getBalancerContractBytecode('20210418-vault', 'Vault')
    const pool_abi = await balancer.getBalancerContractAbi('20210418-weighted-pool', 'WeightedPool')
    const pool_code = await balancer.getBalancerContractBytecode('20210418-weighted-pool', 'WeightedPool')
    const poolfab_abi = await balancer.getBalancerContractAbi('20210418-weighted-pool', 'WeightedPoolFactory')
    const poolfab_code = await balancer.getBalancerContractBytecode('20210418-weighted-pool', 'WeightedPoolFactory')
    vault_type = new ethers.ContractFactory(vault_abi, vault_code, ali)
    poolfab_type = new ethers.ContractFactory(poolfab_abi, poolfab_code, ali)
    pool_type = new ethers.ContractFactory(pool_abi, pool_code, ali)

    vat = await vat_type.deploy()
    plug_join = await plug_join_type.deploy()
    vow = await vow_type.deploy()
    flower = await flower_type.deploy();
    RICO = await gem_type.deploy('Rico', 'RICO')
    RISK = await gem_type.deploy('Rico Riskshare', 'RISK')
    WETH = await gem_type.deploy('Wrapped Ether', 'WETH')
    vault = await vault_type.deploy(ALI, WETH.address, 1000, 1000)
    poolfab = await poolfab_type.deploy(vault.address)

    await send(vat.hope, plug_join.address)
    await send(vat.hope, vow.address)
    await send(vat.rely, plug_join.address)
    await send(vat.rely, vow.address)
    await send(RICO.rely, plug_join.address)
    await send(RISK.rely, vow.address)
    await send(WETH.rely, plug_join.address)

    await send(WETH.mint, ALI, wad(10000))
    await send(RICO.mint, ALI, wad(10000))
    await send(RISK.mint, ALI, wad(10000))
    await send(RICO.approve, plug_join.address, U256_MAX)
    await send(WETH.approve, plug_join.address, U256_MAX)
    await send(WETH.approve, vault.address, U256_MAX)
    await send(RICO.approve, vault.address, U256_MAX)
    await send(RISK.approve, vault.address, U256_MAX)

    await send(plug_join.file_gem, i0, WETH.address)
    await send(plug_join.file_vat, vat.address, true)
    await send(plug_join.file_joy, RICO.address, true)
    await send(plug_join.gem_join, vat.address, i0, ALI, wad(1000))

    await send(vat.init, i0)
    await send(vat.file, b32('ceil'), rad(1000))
    await send(vat.filk, i0, b32('line'), rad(1000))
    await send(vat.filk, i0, b32('liqr'), ray(1))
    await send(vat.filk, i0, b32('chop'), ray(1.1))

    await vow['file(bytes32,address)'](b32('flapper'), flower.address)
    await vow['file(bytes32,address)'](b32('flopper'), flower.address)
    await vow['file(bytes32,address)'](b32('rico'), RICO.address)
    await vow['file(bytes32,address)'](b32('risk'), RISK.address)
    await vow['file(bytes32,address)'](b32('vat'), vat.address)
    await vow['file(bytes32,address)'](b32('vault'), plug_join.address)
    await vow['file(bytes32,uint256)'](b32('bar'), rad(1))
    await send(vow.filk, i0, b32('flipper'), flower.address)
    await send(vow.file_drop, {vel:wad(1), rel:wad(0.001), bel:0, cel:60})
    await send(vow.reapprove)

    await send(vat.plot, i0, ray(1))
    await send(vat.filk, i0, b32('duty'), apy(1.05))
    await send(vat.lock, i0, wad(100))
    await send(vat.draw, i0, wad(99))

    await send(plug_join.joy_exit, vat.address, RICO.address, ALI, wad(99))
    const bal = await RICO.balanceOf(ALI)
    want(bal.toString()).equals(wad(10099).toString())
    const safe1 = await vat.callStatic.safe(i0, ALI)
    want(safe1).true

    // create and add liquidity to weth-rico balancer pool
    let tx_create = await poolfab.create(
        'mock', 'MOCK',
        [WETH.address, RICO.address],
        [wad(0.5), wad(0.5)],
        wad(0.01),
        ALI
    )
    let res = await tx_create.wait()
    let event = res.events[res.events.length - 1]
    let pool_addr = event.args.pool
    pool = pool_type.attach(pool_addr)
    weth_rico_poolId = await pool.getPoolId()
    let JOIN_KIND_INIT = 0
    let initUserData = ethers.utils.defaultAbiCoder.encode(
        ['uint256', 'uint256[]'], [JOIN_KIND_INIT, [wad(1000), wad(1000)]]
    )
    let joinPoolRequest = {
      assets: [WETH.address, RICO.address],
      maxAmountsIn: [wad(1000), wad(1000)],
      userData: initUserData,
      fromInternalBalance: false
    }
    let tx = await vault.joinPool(weth_rico_poolId, ALI, ALI, joinPoolRequest)
    await tx.wait()

    // create and add liquidity to risk-rico balancer pool
    tx_create = await poolfab.create(
        'mock', 'MOCK',
        [RICO.address, RISK.address],
        [wad(0.5), wad(0.5)],
        wad(0.01),
        ALI
    )
    res = await tx_create.wait()
    event = res.events[res.events.length - 1]
    pool_addr = event.args.pool
    pool = pool_type.attach(pool_addr)
    const poolId_risk_rico = await pool.getPoolId()
    JOIN_KIND_INIT = 0
    initUserData = ethers.utils.defaultAbiCoder.encode(
        ['uint256', 'uint256[]'], [JOIN_KIND_INIT, [wad(1000), wad(1000)]]
    )
    joinPoolRequest = {
      assets: [RICO.address, RISK.address],
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
    await send(flower.file, b32('vow'), vow.address)
    await send(flower.setVault, vault.address)
    await send(flower.setPool, WETH.address, RICO.address, weth_rico_poolId)
    await send(flower.setPool, RICO.address, RISK.address, poolId_risk_rico)
    await send(flower.setPool, RISK.address, RICO.address, poolId_risk_rico)
    await send(flower.reapprove)
    await send(flower.approve_gem, WETH.address)

    await snapshot(hh)
  })
  beforeEach(async () => {
    await revert(hh)
  })

  describe('bail urns', () => {
    beforeEach(async () => {
      flower.flip.reset();
    })
    it('vow 1yr not safe bail', async () => {
      await mine(hh, BANKYEAR)

      const safe2 = await vat.callStatic.safe(i0, ALI)
      want(safe2).false

      const sin0 = await vat.sin(vow.address)
      const joy0 = await vat.joy(vow.address)
      const gembal0 = await WETH.balanceOf(flower.address)
      const vow_rico0 = await RICO.balanceOf(vow.address)
      want(sin0.eq(0)).true
      want(joy0.eq(0)).true
      want(gembal0.eq(0)).true
      want(vow_rico0.eq(0)).true

      await send(vow.bail, i0, ALI)

      const [ink, art] = await vat.urns(i0, ALI)
      const sin1 = await vat.sin(vow.address)
      const joy1 = await vat.joy(vow.address)
      const gembal1 = await WETH.balanceOf(flower.address)
      const vow_rico1 = await RICO.balanceOf(vow.address)
      want(ink.eq(0)).true
      want(art.eq(0)).true
      want(sin1.gt(0)).true
      want(joy1.eq(0)).true
      want(vow_rico1.gt(0)).true
      want(gembal1.eq(0)).true
      want(flower.flip).to.have.been.calledOnce
    })

    it('when safe', async () => {
      await fail('ERR_SAFE', vow.bail, i0, ALI)
      want(flower.flip).to.have.callCount(0);
      const sin0 = await vat.sin(vow.address)
      const gembal0 = await WETH.balanceOf(flower.address)
      want(sin0.eq(0)).true
      want(gembal0.eq(0)).true

      await mine(hh, BANKYEAR)
      await send(vow.bail, i0, ALI)
      await fail('ERR_SAFE', vow.bail, i0, ALI)
      want(flower.flip).to.have.been.calledOnce
    })
  })

  describe('keep', () => {
    beforeEach(async () => {
      flower.flip.reset()
      flower.flop.reset()
      flower.flap.reset()
      vat.heal.reset()
    })
    it('vow 1yr drip flap', async () => {
      const initial_total = await RICO.totalSupply()
      await mine(hh, BANKYEAR)
      await send(vat.drip, i0)
      await send(vow.keep)
      const final_total = await RICO.totalSupply()
      want(flower.flap).to.have.callCount(1)
      want(flower.flop).to.have.callCount(0)
      want(vat.heal).to.have.callCount(1)
      want(final_total.gt(initial_total)).true
      // should be interest - 1 for buffer
      want(final_total - initial_total).within(parseInt(wad(3.94).toString()), parseInt(wad(3.96).toString()))
    })
    it('vow 1yr drip with large surplus buffer', async () => {
      // Drew 99 for a year at 5% so surplus should be just under bar of 5
      await vow['file(bytes32,uint256)'](b32('bar'), rad(5))
      await mine(hh, BANKYEAR)
      await send(vat.drip, i0)
      await send(vow.keep)
      want(flower.flap).to.have.callCount(0)
      want(flower.flop).to.have.callCount(0)
      want(vat.heal).to.have.callCount(0)
      await vow['file(bytes32,uint256)'](b32('bar'), rad(4.9))
      await send(vow.keep)
      want(flower.flap).to.have.callCount(1)
      want(flower.flop).to.have.callCount(0)
      want(vat.heal).to.have.callCount(1)
    })
    it('vow 1yr drip flop', async () => {
      await mine(hh, BANKYEAR)
      await send(vow.bail, i0, ALI)
      await send(vow.keep)
      want(flower.flap).to.have.callCount(0)
      want(flower.flop).to.have.callCount(1)
      want(vat.heal).to.have.callCount(1)
    })
    it('only heal when joy == sin', async () => {
      await mine(hh, BANKYEAR)
      await send(vow.bail, i0, ALI)
      vat.sin.returns(rad(1))
      vat.joy.returns(rad(1))
      await send(vow.keep)
      want(flower.flap).to.have.callCount(0)
      want(flower.flop).to.have.callCount(0)
      want(vat.heal).to.have.callCount(1)
      vat.sin.reset();
      vat.joy.reset();
    })

    describe('rate limiting', () => {
      it('flop absolute rate', async () => {
        const risk_supply_0 = await RISK.totalSupply()
        await send(vat.filk, i0, b32('duty'), apy(2))
        await send(vow.file_drop, {vel:wad(0.001), rel:wad(1000000), bel:0, cel:1000})
        await mine(hh, BANKYEAR)
        await send(vow.bail, i0, ALI)
        await send(vow.keep)
        const risk_supply_1 = await RISK.totalSupply()
        await mine(hh, 500)
        await send(vow.keep)
        const risk_supply_2 = await RISK.totalSupply()

        // should have had a mint of the full vel*cel and then half vel*cel
        const mint1 = risk_supply_1 - risk_supply_0
        const mint2 = risk_supply_2 - risk_supply_1
        want(mint1).within(parseInt(wad(0.99).toString()), parseInt(wad(1.01).toString()))
        want(mint2).within(parseInt(wad(0.49).toString()), parseInt(wad(0.51).toString()))
      })

      it('flop relative rate', async () => {
        const risk_supply_0 = await RISK.totalSupply()
        await send(vat.filk, i0, b32('duty'), apy(2))
        // for same results as above the rel rate is set to 1 / risk supply * vel used above
        await send(vow.file_drop, {vel:wad(1000000), rel:wad(0.0000001), bel:0, cel:1000})
        await mine(hh, BANKYEAR)
        await send(vow.bail, i0, ALI)
        await send(vow.keep)
        const risk_supply_1 = await RISK.totalSupply()
        await mine(hh, 500)
        await send(vow.keep)
        const risk_supply_2 = await RISK.totalSupply()

        // should have had a mint of the full vel*cel and then half vel*cel
        const mint1 = risk_supply_1 - risk_supply_0
        const mint2 = risk_supply_2 - risk_supply_1
        want(mint1).within(parseInt(wad(0.999).toString()), parseInt(wad(1.000).toString()))
        want(mint2).within(parseInt(wad(0.497).toString()), parseInt(wad(0.503).toString()))
      })
    })
  })

  describe('end to end', () => {
    beforeEach(async () => {
      flower.flip.reset()
      flower.flop.reset()
      flower.flap.reset()
      vat.heal.reset()
    })

    it('all actions', async () => {
      // run a flap and ensure risk is burnt
      const risk_initial_supply = await RISK.totalSupply()
      await mine(hh, BANKYEAR)
      await send(vat.drip, i0)
      await send(vow.keep)
      await mine(hh, 60)
      await send(vat.drip, i0)
      await send(vow.keep)  // call again to burn risk given to vow the first time
      const risk_post_flap_supply = await RISK.totalSupply()
      want(risk_post_flap_supply.lt(risk_initial_supply)).true
      want(flower.flip).to.have.callCount(0)
      want(flower.flop).to.have.callCount(0)
      want(flower.flap).to.have.callCount(2)

      // confirm bail trades the weth for rico
      let pre_bail_pool_tokens = await vault.getPoolTokens(weth_rico_poolId)
      await send(vow.bail, i0, ALI)
      let post_bail_tokens = await vault.getPoolTokens(weth_rico_poolId)
      want(pre_bail_pool_tokens[0] < post_bail_tokens[0])
      want(pre_bail_pool_tokens[1] > post_bail_tokens[1])

      // although the keep joins the rico sin is still greater due to fees so we flop
      await send(vow.keep)
      want(flower.flip).to.have.callCount(1)
      want(flower.flop).to.have.callCount(1)
      want(flower.flap).to.have.callCount(2)
      // now vow should hold more rico than anti tokens
      const sin = await vat.sin(vow.address)
      const vow_rico = await RICO.balanceOf(vow.address)
      want(vow_rico * 10**27 > sin)
    })
  })
})
