const debug = require('debug')('ricobank:task')

import { task } from 'hardhat/config'
import { PackBuilder } from 'dpack'

task('deploy-ricobank', '')
.addOptionalParam('mock', 'Ignore dependency args and deploy new mock dependencies')
.addOptionalParam('dependencies', 'Pack with all required dependencies')
.setAction(async (args, hre) => {
  debug('network name in task:', hre.network.name)
  const [ALI] = await hre.ethers.getSigners();

  if (args.mock && args.dependencies) {
    throw new Error(`Panic: don't use 'mock' and 'dependencies' together`)
  }
  let deps
  if (args.dependencies) {
    deps = args.dependencies
  } else if (args.mock) {
    deps = await hre.run('deploy-mock-dependencies')
  } else {
    throw new Error(`Panic: must provide either 'mock' or 'dependencies'`)
  }

  const vat_artifact = require('../artifacts/sol/vat.sol/Vat.json')
  const vat_deployer = hre.ethers.ContractFactory.fromSolidity(vat_artifact, ALI);

  const pb = new PackBuilder(hre.network.name);

  const vat = await vat_deployer.deploy();
  await pb.packObject({
    objectname: 'vat',
    address: vat.address,
    typename: 'Vat',
    artifact: vat_artifact
  });

  const pack = await pb.build();
  return pack;
});
