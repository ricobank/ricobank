const debug = require('debug')('rico:deploy')

const dpack = require('dpack')

const { task, subtask } = require('hardhat/config')

subtask('deploy-gemfab', 'deploy token factory')
.setAction(async (args, hre) => {
});

task('deploy-autobank', 'initial system deployment')
.addParam('name', 'system name to prefix object names')
.addParam('feedbasePack', 'feedbase dpack path (dependency)')
.addParam('bankPack', 'bank dpack path to save output')
.setAction(async (args, hre) => {
  const { ethers, network } = hre;

  const [acct] = await hre.ethers.getSigners();
  console.log(`Deploying from address ${acct.address} to network ${network.name}`)

  await dpack.mutatePackFile(args.feedbasePack, args.bankPack, async (mutator) => {

    const VatArtifact = await hre.artifacts.readArtifact('Vat')
    const VatDeployer = await hre.ethers.getContractFactory('Vat')
    const vat = await VatDeployer.deploy();
    await vat.deployed();

    await mutator.addType(VatArtifact);
    await mutator.addObject(args.name + '_VAT', vat.address, network.name, VatArtifact);

    console.log('Vat deployed to: ', vat.address);

  });

  console.log('Done!')
  
})

export {}
