const balancer = require('@balancer-labs/v2-deployments')
import { PackBuilder } from 'dpack'

import {task} from 'hardhat/config'
import {HardhatRuntimeEnvironment, TaskArguments} from 'hardhat/types'

task('deploy-mock-balancer', 'deploys balancer Vault and WeightedPoolFactory')
.addFlag('stdout', 'log the dpack to stdout')
.addOptionalParam('outfile', 'write the dpack to an output file')
.setAction(async (args: TaskArguments, hre: HardhatRuntimeEnvironment) => {
  const {ethers, network} = hre
  const [acct] = await hre.ethers.getSigners()
  const deployer = acct.address
  const weth_pack = args.weth_pack

  const vault_abi = await balancer.getBalancerContractAbi('20210418-vault', 'Vault')
  const vault_code = await balancer.getBalancerContractBytecode('20210418-vault', 'Vault')
  const poolfab_abi = await balancer.getBalancerContractAbi('20210418-weighted-pool', 'WeightedPoolFactory')
  const poolfab_code = await balancer.getBalancerContractBytecode('20210418-weighted-pool', 'WeightedPoolFactory')

  const vault_type = new ethers.ContractFactory(vault_abi, vault_code, acct)
  const poolfab_type = new ethers.ContractFactory(poolfab_abi, poolfab_code, acct)

  const vault = await vault_type.deploy(deployer, weth_pack.objects.weth9.address, 1000, 1000)
  const poolfab = await poolfab_type.deploy(vault.address)

  const pb = new PackBuilder(network.name)
  await pb.packObject({
    objectname: 'bal2_vault',
    address: vault.address,
    typename: 'Bal2Vault',
    artifact: {
      abi: vault_abi,
      bytecode: vault_code
    }
  })
  await pb.packObject({
    objectname: 'bal2_weighted_pool_fab',
    address: poolfab.address,
    typename: 'Bal2WeightedPoolFactory',
    artifact: {
      abi: poolfab_abi,
      bytecode: poolfab_code
    }
  })

  const pack = await pb.build();
  const str = JSON.stringify(pack, null, 2)
  if (args.stdout) {
    console.log(str)
  }
  if (args.outfile) {
    require('fs').writeFileSync(args.outfile)
  }
  return pack
})
