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

describe('Gas', () => {
  let ali, bob, cat
  let ALI, BOB, CAT
  let bank, ball
  let risk, rico
  let pack
  let deploygas
  let dapp

  before(async () => {
    [ali, bob, cat] = await ethers.getSigners();
    [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address)

    const risk_mint = wad(100000)
    ;[deploygas, pack] = await task_total_gas(hh, 'deploy-ricobank', {mock:'true', netname: 'ethereum', mint: risk_mint})
    dapp = await dpack.load(pack, ethers, ali)

    bank = dapp.bank
    ball = dapp.ball
    risk = dapp.risk
    rico = dapp.rico
    risk = dapp.risk

    await snapshot_name(hh);
  })

  afterEach(async () => revert_name(hh))
  after(async () => {
      revert_pop(hh)
      revert_clear(hh)
  })

  describe('gas', () => {
    async function check(gas, minGas, maxGas?) {
      if (!maxGas) maxGas = minGas
      await want(gas.toNumber()).to.be.at.most(maxGas);
      if (gas.toNumber() < minGas) {
        console.log("gas reduction: previous min=", minGas, " gas used=", gas.toNumber());
      }
    }

    it('deploy gas', async () => {
      await check(ethers.BigNumber.from(deploygas), 5751191)
    })

    it('frob cold gas', async () => {
      let dink = ethers.utils.solidityPack(['int'], [wad(5)])
      let gas = await bank.estimateGas.frob(ALI, dink, wad(2))
      await check(gas, 218359)
    })

    it('frob hot gas', async () => {
      let dink = ethers.utils.solidityPack(['int'], [wad(5)])
      await send(bank.frob, ALI, dink, wad(2), {gasLimit: 30000000})
      await mine(hh, 100)
      await send(bank.frob, ALI, 0, 0)
      let gas = await bank.estimateGas.frob(
        ALI, ethers.utils.solidityPack(['int'], [wad(5)]), wad(2)
      )
      await check(gas, 118283)
    })

    it('bail gas', async () => {
      let dink = ethers.utils.solidityPack(['int'], [wad(5)])
      await send(bank.frob, ALI, dink, wad(2))

      await mine(hh, BANKYEAR * 1000)

      let gas = await bank.estimateGas.bail(ALI)
      await check(gas, 169274)
    })

    it('keep surplus gas', async () => {
      let dink = ethers.utils.solidityPack(['int'], [wad(5)])
      await send(bank.frob, ALI, dink, wad(1))
      await mine(hh, BANKYEAR)
      let gas = await bank.estimateGas.keep()
      await check(gas, 147644)
    })

  })
})
