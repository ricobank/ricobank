import { expect as want } from 'chai'

import * as hh from 'hardhat'
import { ethers } from 'hardhat'
import { smock } from '@defi-wonderland/smock'

import { b32, snapshot, revert, file_ramp, filem_ramp } from './helpers'
import { fail, mine, wad, ray, rad, apy, send, BANKYEAR, U256_MAX } from 'minihat'

const dpack = require('@etherpacks/dpack')

const chai = require('chai')
chai.use(smock.matchers)
const i0 = Buffer.alloc(32) // ilk 0 id

describe('vow / liq liquidation lifecycle', () => {
  let ali, bob, cat
  let ALI, BOB, CAT
  let RICO, RISK, WETH, XETH
  let vat; let vat_type
  let plug
  let port
  let vow
  let flower; let flower_type
  let mock_flower_plopper; let mock_flower_plopper_type
  let vault
  let poolId_weth_rico
  let poolId_xeth_rico
  let poolId_risk_rico
  before(async () => {
    [ali, bob, cat] = await ethers.getSigners();
    [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address)

    const pack = await hh.run('deploy-ricobank', { mock: 'true' })
    const dapp = await dpack.load(pack, ethers)

    flower_type = await smock.mock('RicoFlowerV1', { signer: ali })
    mock_flower_plopper_type = await ethers.getContractFactory('MockFlowerPlopper', ali)
    vat_type = await smock.mock('Vat', { signer: ali })

    const gem_artifact = await dpack.getIpfsJson(pack.types.Gem.artifact['/'])
    const receipt = await send(dapp.gemfab.build, 'Weth Plus', 'XETH')
    const [, gem_address] = receipt.events.find(event => event.event === 'Build').args
    XETH = new ethers.Contract(gem_address, gem_artifact.abi, ali)

    plug = dapp.plug
    port = dapp.port
    vault = dapp.vault
    vow = dapp.vow
    RICO = dapp.rico
    RISK = dapp.risk
    WETH = dapp.weth

    vat = await vat_type.deploy()
    flower = await flower_type.deploy()
    mock_flower_plopper = await mock_flower_plopper_type.deploy()

    await send(vat.trust, port.address, true)
    await send(vat.trust, vow.address, true)
    await send(vat.ward, plug.address, true)
    await send(vat.ward, vow.address, true)
    await send(RICO.ward, port.address, true)
    await send(RISK.ward, vow.address, true)

    await send(WETH.deposit, { value: ethers.utils.parseEther('6000.0') })
    await send(XETH.mint, ALI, wad(10000))
    await send(RICO.mint, ALI, wad(10000))
    await send(RISK.mint, ALI, wad(10000))
    await send(WETH.approve, plug.address, U256_MAX)
    await send(XETH.approve, plug.address, U256_MAX)

    await send(plug.bind, vat.address, i0, WETH.address, true)
    await send(plug.bind, vat.address, i0, XETH.address, true)
    await send(port.bind, vat.address, RICO.address, true)
    await send(plug.join, vat.address, i0, WETH.address, ALI, wad(1000))
    await send(plug.join, vat.address, i0, XETH.address, ALI, wad(1000))
    await send(vat.init, i0)
    await send(vat.file, b32('ceil'), rad(2000))
    await send(vat.filk, i0, b32('line'), rad(2000))
    await send(vat.filk, i0, b32('liqr'), ray(1))
    await send(vat.filk, i0, b32('chop'), ray(1.1))

    await send(vow.file, b32('bar'), rad(1))
    await send(vow.link, b32('flapper'), flower.address)
    await send(vow.link, b32('flopper'), flower.address)
    await send(vow.link, b32('plug'), plug.address)
    await send(vow.link, b32('port'), port.address)
    await send(vow.link, b32('rico'), RICO.address)
    await send(vow.link, b32('risk'), RISK.address)
    await send(vow.link, b32('vat'), vat.address)
    await send(vow.lilk, i0, b32('flipper'), flower.address)
    await file_ramp(vow, { vel: wad(1), rel: wad(0.001), bel: 0, cel: 60 })

    await send(vow.reapprove)
    await send(vow.reapprove_gem, WETH.address)
    await send(vow.reapprove_gem, XETH.address)

    await send(vat.plot, i0, ray(1))
    await send(vat.filk, i0, b32('duty'), apy(1.05))
    await send(vat.lock, i0, wad(100))
    await send(vat.draw, i0, wad(99))

    await send(port.exit, vat.address, RICO.address, ALI, wad(99))
    const bal = await RICO.balanceOf(ALI)
    want(bal.toString()).equals(wad(10099).toString())
    const safe1 = await vat.callStatic.safe(i0, ALI)
    want(safe1).true

    await send(WETH.approve, vault.address, U256_MAX)
    await send(XETH.approve, vault.address, U256_MAX)
    await send(RICO.approve, vault.address, U256_MAX)
    await send(RISK.approve, vault.address, U256_MAX)

    const weth_rico_tokens = [{token: WETH, weight: wad(0.5), amountIn: wad(2000)},
                              {token: RICO, weight: wad(0.5), amountIn: wad(2000)}]
    const xeth_rico_tokens = [{token: XETH, weight: wad(0.5), amountIn: wad(2000)},
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
    const xeth_rico_args = {
      balancer_pack: pack,
      token_settings: xeth_rico_tokens,
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
    poolId_xeth_rico = (await hh.run('build-weighted-bpool', xeth_rico_args)).pool_id
    poolId_risk_rico = (await hh.run('build-weighted-bpool', risk_rico_args)).pool_id

    await filem_ramp(WETH, flower, { vel: wad(1), rel: wad(0.001), bel: 0, cel: 600 })
    await filem_ramp(XETH, flower, { vel: wad(1), rel: wad(0.001), bel: 0, cel: 600 })
    await filem_ramp(RICO, flower, { vel: wad(1), rel: wad(0.001), bel: 0, cel: 600 })
    await send(flower.link, b32('rico'), RICO.address)
    await send(flower.link, b32('risk'), RISK.address)
    await send(flower.link, b32('vow'), vow.address)
    await send(flower.setVault, vault.address)
    await send(flower.setPool, WETH.address, RICO.address, poolId_weth_rico)
    await send(flower.setPool, XETH.address, RICO.address, poolId_xeth_rico)
    await send(flower.setPool, RICO.address, RISK.address, poolId_risk_rico)
    await send(flower.setPool, RISK.address, RICO.address, poolId_risk_rico)
    await send(flower.reapprove)
    await send(flower.approve_gem, WETH.address)
    await send(flower.approve_gem, XETH.address)

    await snapshot(hh)
  })
  beforeEach(async () => {
    await revert(hh)
  })

  describe('bail urns', () => {
    beforeEach(async () => {
      flower.flip.reset()
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

      await send(vow.bail, i0, [WETH.address], ALI)

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
      want(flower.flip).to.have.been.called
    })

    it('when safe', async () => {
      await fail('ERR_SAFE', vow.bail, i0, [WETH.address], ALI)
      want(flower.flip).to.have.callCount(0)
      const sin0 = await vat.sin(vow.address)
      const gembal0 = await WETH.balanceOf(flower.address)
      want(sin0.eq(0)).true
      want(gembal0.eq(0)).true

      await mine(hh, BANKYEAR)
      await send(vow.bail, i0, [WETH.address], ALI)
      await fail('ERR_SAFE', vow.bail, i0, [WETH.address], ALI)
      want(flower.flip).to.have.been.called
    })

    it('shared ilk bail', async () => {
      await send(vat.lock, i0, wad(1000))
      await send(vat.draw, i0, wad(1000))
      // ink now exceeds quantity available from WETH alone, need to use both gems to bail in this case.
      await mine(hh, BANKYEAR)
      await fail('MISSING_GEM', vow.bail, i0, [WETH.address], ALI)
      await send(vow.bail, i0, [WETH.address, XETH.address], ALI)
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
      want(flower.flap).to.have.been.called
      want(flower.flop).to.have.callCount(0)
      want(vat.heal).to.have.been.called
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
      want(flower.flap).to.have.been.called
      want(flower.flop).to.have.callCount(0)
      want(vat.heal).to.have.been.called
    })
    it('vow 1yr drip flop', async () => {
      await mine(hh, BANKYEAR)
      await send(vow.bail, i0, [WETH.address], ALI)
      await send(vow.keep)
      want(flower.flap).to.have.callCount(0)
      want(flower.flop).to.have.been.called
      want(vat.heal).to.have.been.called
    })
    it('only heal when joy == sin', async () => {
      await mine(hh, BANKYEAR)
      await send(vow.bail, i0, [WETH.address], ALI)
      vat.sin.returns(rad(1))
      vat.joy.returns(rad(1))
      await send(vow.keep)
      want(flower.flap).to.have.callCount(0)
      want(flower.flop).to.have.callCount(0)
      want(vat.heal).to.have.been.called
      vat.sin.reset()
      vat.joy.reset()
    })

    describe('rate limiting', () => {
      it('flop absolute rate', async () => {
        const risk_supply_0 = await RISK.totalSupply()
        await send(vat.filk, i0, b32('duty'), apy(2))
        await file_ramp(vow, { vel: wad(0.001), rel: wad(1000000), bel: 0, cel: 1000 })
        await mine(hh, BANKYEAR)
        await send(vow.bail, i0, [WETH.address], ALI)
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
        await file_ramp(vow, { vel: wad(1000000), rel: wad(0.0000001), bel: 0, cel: 1000 })
        await mine(hh, BANKYEAR)
        await send(vow.bail, i0, [WETH.address], ALI)
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
      await send(vow.bail, i0, [WETH.address], ALI)
      await fail('ERR_SAFE', vow.bail, i0, [WETH.address], ALI)
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
      await send(vow.keep) // call again to burn risk given to vow the first time
      const risk_post_flap_supply = await RISK.totalSupply()
      want(risk_post_flap_supply.lt(risk_initial_supply)).true
      want(flower.flip).to.have.callCount(0)
      want(flower.flop).to.have.callCount(0)
      want(flower.flap).to.have.been.called

      // confirm bail trades the weth for rico
      const vow_rico_0 = await RICO.balanceOf(vow.address)
      const plug_weth_0 = await WETH.balanceOf(plug.address)
      await send(vow.bail, i0, [WETH.address], ALI)
      const vow_rico_1 = await RICO.balanceOf(vow.address)
      const plug_weth_1 = await WETH.balanceOf(plug.address)
      want(vow_rico_1.gt(vow_rico_0)).true
      want(plug_weth_0.gt(plug_weth_1)).true
      want(flower.flip).to.have.been.called
      want(flower.flop).to.have.callCount(0)
      want(flower.flap).to.have.been.called

      // although the keep joins the rico sin is still greater due to fees so we flop
      await send(vow.keep)
      want(flower.flip).to.have.been.called
      want(flower.flop).to.have.been.called
      want(flower.flap).to.have.been.called
      // now vow should hold more rico than anti tokens
      const sin = await vat.sin(vow.address)
      const vow_rico = await RICO.balanceOf(vow.address)
      want(vow_rico * 10**27 > sin)
    })
  })
})
