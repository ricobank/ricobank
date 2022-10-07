import * as hh from 'hardhat'
import { ethers } from 'hardhat'

describe('ball', () => {
  it('deploys', async () => {
    const deps = await hh.run('deploy-mock-dependencies')
    const ball_type = await ethers.getContractFactory('Ball')
    const ball = await ball_type.deploy(deps.objects.gemfab.address, deps.objects.feedbase.address,
        deps.objects.weth.address, deps.objects.weighted_pool_factory.address, deps.objects.vault.address)
    const tx = await ball.deployTransaction.wait()
    const gas = tx.gasUsed
    console.log(`cannonball cost: ${gas.toString()}`)
  })
})
