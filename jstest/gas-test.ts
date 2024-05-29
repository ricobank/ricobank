const debug = require('debug')('rico:test')
import { expect as want } from 'chai'
import { task_total_gas } from './helpers'

import * as hh from 'hardhat'
// @ts-ignore
import { ethers } from 'hardhat'
import { constants } from 'ethers'

import { send, fail, wad, ray, rad, BANKYEAR, warp, mine } from 'minihat'
const { hexZeroPad } = ethers.utils

import { b32, revert_pop, revert_name, revert_clear, snapshot_name, join_pool, gettime } from './helpers'
const dpack = require('@etherpacks/dpack')

const bn2b32 = (bn) => hexZeroPad(bn.toHexString(), 32)
const TAG = Buffer.from('feed'.repeat(16), 'hex')

describe('Gas', () => {
  let ali, bob, cat
  let ALI, BOB, CAT
  let bank, ball
  let risk, rico, risk
  let pack
  let deploygas
  let dapp
  let dai

  const rilk = b32('risk')

  before(async () => {
    [ali, bob, cat] = await ethers.getSigners();
    [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address)

    ;[deploygas, pack] = await task_total_gas(hh, 'deploy-ricobank', {mock:'true', netname: 'ethereum', tokens: './tokens.json'})
    dapp = await dpack.load(pack, ethers, ali)

    bank = dapp.bank
    ball = dapp.ball
    risk = dapp.risk
    rico = dapp.rico
    risk = dapp.risk
    dai  = dapp.dai

    await send(bank.file, b32('par'), b32(wad(7)))

    await send(risk.mint, ALI, wad(100))
    await send(risk.approve, bank.address, constants.MaxUint256)
    await send(risk.mint, ALI, wad(100000));

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

    beforeEach(async () => {
      await send(bank.file, b32('par'), b32(ray(1)))
    })

    it('deploy gas', async () => {
      await check(ethers.BigNumber.from(deploygas), 13664918)
    })

    it('frob cold gas', async () => {
      let dink = ethers.utils.solidityPack(['int'], [wad(5)])
      let gas = await bank.estimateGas.frob(rilk, ALI, dink, wad(2))
      await check(gas, 285750)
    })

    it('frob hot gas', async () => {
      let dink = ethers.utils.solidityPack(['int'], [wad(5)])
      await send(bank.frob, rilk, ALI, dink, wad(2))
      await mine(hh, 100)
      await send(bank.drip, rilk)
      let gas = await bank.estimateGas.frob(
        rilk, ALI, ethers.utils.solidityPack(['int'], [wad(5)]), wad(2)
      )
      await check(gas, 148940)
    })

    it('bail gas', async () => {
      let dink = ethers.utils.solidityPack(['int'], [wad(5)])
      await send(bank.frob, rilk, ALI, dink, wad(2))

      await mine(hh, BANKYEAR * 1000)

      let gas = await bank.estimateGas.bail(rilk, ALI)
      await check(gas, 203287)
    })

    it('keep surplus gas', async () => {
      const FEE_2X_ANN = bn2b32(ethers.BigNumber.from('1000000021964508944519921664'))
      await send(bank.filk, rilk, b32('fee'), FEE_2X_ANN)
      await send(rico.mint, ALI, wad(100000))

      let dink = ethers.utils.solidityPack(['int'], [wad(5)])
      await send(bank.frob, rilk, ALI, dink, wad(1))

      await mine(hh, BANKYEAR * 3)
      await send(bank.bail, rilk, ALI)

      dink = ethers.utils.solidityPack(['int'], [wad(40)])
      await send(bank.frob, rilk, ALI, dink, wad(4))

      await mine(hh, BANKYEAR)
      await send(bank.drip, rilk)

      let timestamp = (await ali.provider.getBlock('latest')).timestamp
      await send(bank.file, b32('dam'), bn2b32(ray(1).div(wad(1))))
      await send(bank.file, b32('bel'), bn2b32(ethers.BigNumber.from(timestamp)))
      let gas = await bank.estimateGas.keep([])
      await check(gas, 125984)
    })

    it('drip gas', async () => {
      let dink = ethers.utils.solidityPack(['int'], [wad(5)])
      await send(bank.frob, rilk, ALI, dink, wad(2))
      await mine(hh, BANKYEAR)
      let gas = await bank.estimateGas.drip(rilk)
      await check(gas, 91694, 91694)
    })
  })
})
