// balancer mock setup test

import { send, wad, U256_MAX } from './helpers'

import { ethers } from 'hardhat'

const debug = require('debug')('rico:test')
const want = require('chai').expect

const balancer = require('@balancer-labs/v2-deployments')

describe('bal balancer setup test', () => {
  let gem_type
  let WETH
  let RICO
  let ali, bob, cat
  let ALI, BOB, CAT
  let vault_type
  let poolfab_type
  let pool_type
  let vault
  let poolfab
  let pool
  before(async () => {
    [ali, bob, cat] = await ethers.getSigners();
    [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address)

    const gem_artifacts = require('../lib/gemfab/artifacts/sol/gem.sol/Gem.json')
    gem_type = ethers.ContractFactory.fromSolidity(gem_artifacts, ali)

    const vault_abi = await balancer.getBalancerContractAbi('20210418-vault', 'Vault')
    const vault_code = await balancer.getBalancerContractBytecode('20210418-vault', 'Vault')

    const pool_abi = await balancer.getBalancerContractAbi('20210418-weighted-pool', 'WeightedPool')
    const pool_code = await balancer.getBalancerContractBytecode('20210418-weighted-pool', 'WeightedPool')

    const poolfab_abi = await balancer.getBalancerContractAbi('20210418-weighted-pool', 'WeightedPoolFactory')
    const poolfab_code = await balancer.getBalancerContractBytecode('20210418-weighted-pool', 'WeightedPoolFactory')

    vault_type = new ethers.ContractFactory(vault_abi, vault_code, ali)
    poolfab_type = new ethers.ContractFactory(poolfab_abi, poolfab_code, ali)
    pool_type = new ethers.ContractFactory(pool_abi, pool_code, ali)
  })
  beforeEach(async () => {
    WETH = await gem_type.deploy('Wrapped Ether', 'WETH')
    RICO = await gem_type.deploy('Rico', 'RICO')
    vault = await vault_type.deploy(ALI, WETH.address, 1000, 1000)
    poolfab = await poolfab_type.deploy(vault.address)

    await send(WETH.mint, ALI, wad(10000))
    await send(RICO.mint, ALI, wad(10000))
    await send(WETH.approve, vault.address, U256_MAX)
    await send(RICO.approve, vault.address, U256_MAX)
  })
  it('bal pool setup', async () => {
    const tx_create = await poolfab.create(
      'mock', 'MOCK',
      [WETH.address, RICO.address],
      [wad(0.5), wad(0.5)],
      wad(0.01),
      ALI
    )
    const res = await tx_create.wait()
    const event = res.events[res.events.length - 1]
    const pool_addr = event.args.pool

    pool = pool_type.attach(pool_addr)
    const poolId = await pool.getPoolId()

    const JOIN_KIND_INIT = 0
    const initUserData = ethers.utils.defaultAbiCoder.encode(
      ['uint256', 'uint256[]'], [JOIN_KIND_INIT, [wad(100), wad(100)]]
    )
    const joinPoolRequest = {
      assets: [WETH.address, RICO.address],
      maxAmountsIn: [wad(100), wad(100)],
      userData: initUserData,
      fromInternalBalance: false
    }

    const tx = await vault.joinPool(poolId, ALI, ALI, joinPoolRequest)
    await tx.wait()

    const SWAP_KIND = 0 // GIVEN_IN

    const swapStruct = {
      poolId: poolId,
      kind: SWAP_KIND,
      assetIn: WETH.address,
      assetOut: RICO.address,
      amount: wad(1),
      userData: '0x'
    }

    const fundStruct = {
      sender: ALI,
      fromInternalBalance: false,
      recipient: ALI,
      toInternalBalance: false
    }

    const tokenLimit = wad(0.1)

    const weth_before = await WETH.balanceOf(ALI)
    const rico_before = await RICO.balanceOf(ALI)

    const tx_swap = await vault.swap(swapStruct, fundStruct, tokenLimit, Date.now() + 100000)
    await tx_swap.wait()

    const weth_after = await WETH.balanceOf(ALI)
    const rico_after = await RICO.balanceOf(ALI)

    want(weth_after.lt(weth_before)).true
    want(rico_after.gt(rico_before)).true
  })
})
