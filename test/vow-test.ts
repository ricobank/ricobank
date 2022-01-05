import { expect as want } from 'chai'

import * as hh from 'hardhat'
import { ethers } from 'hardhat'
import { smock } from '@defi-wonderland/smock'

const chai = require('chai');
chai.use(smock.matchers);

import {b32, snapshot, revert, file_ramp, filem_ramp} from './helpers'
import { fail, mine, wad, ray, rad, apy, send, BANKYEAR, U256_MAX } from 'minihat'
const i0 = Buffer.alloc(32) // ilk 0 id

describe('vow / liq liquidation lifecycle', () => {
  let ali, bob, cat
  let ALI, BOB, CAT
  let RICO, RISK, WETH; let gem_type
  let vat; let vat_type
  let join, join_type
  let port, port_type
  let vow; let vow_type
  let flower; let flower_type;
  let mock_flower_plopper; let mock_flower_plopper_type;
  let vault
  let poolId_weth_rico
  let poolId_risk_rico
  before(async () => {
    [ali, bob, cat] = await ethers.getSigners();
    [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address)
    const gem_artifacts = require('../lib/gemfab/artifacts/sol/gem.sol/Gem.json')
    gem_type = ethers.ContractFactory.fromSolidity(gem_artifacts, ali)
    vat_type = await smock.mock('Vat', ali)
    vow_type = await ethers.getContractFactory('Vow', ali)
    join_type = await ethers.getContractFactory('Join', ali)
    port_type = await ethers.getContractFactory('Port', ali)
    flower_type = await smock.mock('RicoFlowerV1')
    mock_flower_plopper_type = await ethers.getContractFactory('MockFlowerPlopper', ali)

    vat = await vat_type.deploy()
    join = await join_type.deploy()
    port = await port_type.deploy()
    vow = await vow_type.deploy()
    flower = await flower_type.deploy();
    mock_flower_plopper = await mock_flower_plopper_type.deploy();
    RICO = await gem_type.deploy('Rico', 'RICO')
    RISK = await gem_type.deploy('Rico Riskshare', 'RISK')
    WETH = await gem_type.deploy('Wrapped Ether', 'WETH')

    await send(vat.hope, port.address)
    await send(vat.hope, vow.address)
    await send(vat.ward, join.address, true)
    await send(vat.ward, vow.address, true)
    await send(RICO.ward, port.address, true)
    await send(RISK.ward, vow.address, true)

    await send(WETH.mint, ALI, wad(10000))
    await send(RICO.mint, ALI, wad(10000))
    await send(RISK.mint, ALI, wad(10000))
    await send(WETH.approve, join.address, U256_MAX)

    await send(join.bind, vat.address, i0, WETH.address)
    await send(port.bind, vat.address, RICO.address, true)
    await send(join.join, vat.address, i0, ALI, wad(1000))
    await send(vat.init, i0)
    await send(vat.file, b32('ceil'), rad(1000))
    await send(vat.filk, i0, b32('line'), rad(1000))
    await send(vat.filk, i0, b32('liqr'), ray(1))
    await send(vat.filk, i0, b32('chop'), ray(1.1))

    await send(vow.file, b32('bar'), rad(1))
    await send(vow.link, b32('flapper'), flower.address)
    await send(vow.link, b32('flopper'), flower.address)
    await send(vow.link, b32('join'), join.address)
    await send(vow.link, b32('port'), port.address)
    await send(vow.link, b32('rico'), RICO.address)
    await send(vow.link, b32('risk'), RISK.address)
    await send(vow.link, b32('vat'), vat.address)
    await send(vow.lilk, i0, b32('flipper'), flower.address)
    await file_ramp(vow, {'vel': wad(1), 'rel': wad(0.001), 'bel': 0, 'cel': 60})

    await send(vow.reapprove)
    await send(vow.reapprove_gem, WETH.address)

    await send(vat.plot, i0, ray(1))
    await send(vat.filk, i0, b32('duty'), apy(1.05))
    await send(vat.lock, i0, wad(100))
    await send(vat.draw, i0, wad(99))

    await send(port.exit, vat.address, RICO.address, ALI, wad(99))
    const bal = await RICO.balanceOf(ALI)
    want(bal.toString()).equals(wad(10099).toString())
    const safe1 = await vat.callStatic.safe(i0, ALI)
    want(safe1).true

    const task_args = { WETH: WETH }
    const balancer_pack = await hh.run('deploy-mock-balancer', task_args)
    vault = balancer_pack.vault

    await send(WETH.approve, vault.address, U256_MAX)
    await send(RICO.approve, vault.address, U256_MAX)
    await send(RISK.approve, vault.address, U256_MAX)

    const weth_rico_tokens = [{token: WETH, weight: wad(0.5), amountIn: wad(2000)},
                              {token: RICO, weight: wad(0.5), amountIn: wad(2000)}]
    const risk_rico_tokens = [{token: RISK, weight: wad(0.5), amountIn: wad(2000)},
                              {token: RICO, weight: wad(0.5), amountIn: wad(2000)}]
    const weth_rico_args = {
      balancer_pack: balancer_pack,
      token_settings: weth_rico_tokens,
      name: 'mock',
      symbol: 'MOCK',
      swapFeePercentage: wad(0.01)
    }
    const risk_rico_args = {
      balancer_pack: balancer_pack,
      token_settings: risk_rico_tokens,
      name: 'mock',
      symbol: 'MOCK',
      swapFeePercentage: wad(0.01)
    }
    poolId_weth_rico = (await hh.run('deploy-balancer-pool', weth_rico_args)).pool_id
    poolId_risk_rico = (await hh.run('deploy-balancer-pool', risk_rico_args)).pool_id

    await filem_ramp(WETH, flower, {'vel': wad(1), 'rel': wad(0.001), 'bel': 0, 'cel': 600})
    await filem_ramp(RICO, flower, {'vel': wad(1), 'rel': wad(0.001), 'bel': 0, 'cel': 600})
    await send(flower.link, b32('rico'), RICO.address)
    await send(flower.link, b32('risk'), RISK.address)
    await send(flower.link, b32('vow'), vow.address)
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
        await file_ramp(vow, {'vel': wad(0.001), 'rel': wad(1000000), 'bel': 0, 'cel': 1000})
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
        await file_ramp(vow, {'vel': wad(1000000), 'rel': wad(0.0000001), 'bel': 0, 'cel': 1000})
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

  describe('plop', () => {
    beforeEach(async () => {
      await send(mock_flower_plopper.file, b32('rico'), RICO.address)
      await send(mock_flower_plopper.file, b32('vow'), vow.address)
      await send(mock_flower_plopper.setVault, vault.address)
      await send(mock_flower_plopper.setPool, WETH.address, RICO.address, poolId_weth_rico)
      await send(mock_flower_plopper.setPool, RICO.address, WETH.address, poolId_weth_rico)
      await send(mock_flower_plopper.approve_gem, WETH.address)
      await send(vow.ward, mock_flower_plopper.address, true)
      await send(vow.lilk, i0, b32('flipper'), mock_flower_plopper.address)
      await send(vat.filk, i0, b32('liqr'), ray(0.8))
      await send(vat.lock, i0, wad(25))
    })
    it('gems are given back to liquidated user', async () => {
      const usr_gems_0 = await vat.gem(i0, ALI)
      await mine(hh, BANKYEAR)
      await send(vow.bail, i0, ALI)
      await fail('ERR_SAFE', vow.bail, i0, ALI)
      const usr_gems_1 = await vat.gem(i0, ALI)
      want(usr_gems_0.eq(usr_gems_1)).true
      await send(mock_flower_plopper.complete_auction, 1)
      const usr_gems_2 = await vat.gem(i0, ALI)
      const sin1 = await vat.sin(vow.address)
      const vow_rico1 = await RICO.balanceOf(vow.address)
      const sin_wad = sin1 / 10**27
      want(sin_wad < vow_rico1).true
      want(usr_gems_0.lt(usr_gems_2)).true
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
      const vow_rico_0 = await RICO.balanceOf(vow.address)
      const join_weth_0 = await WETH.balanceOf(join.address)
      await send(vow.bail, i0, ALI)
      const vow_rico_1 = await RICO.balanceOf(vow.address)
      const join_weth_1 = await WETH.balanceOf(join.address)
      want(vow_rico_1.gt(vow_rico_0)).true
      want(join_weth_0.gt(join_weth_1)).true
      want(flower.flip).to.have.callCount(1)
      want(flower.flop).to.have.callCount(0)
      want(flower.flap).to.have.callCount(2)

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