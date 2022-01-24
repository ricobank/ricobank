import { task } from 'hardhat/config'
import { send } from 'minihat'

const debug = require('debug')('ricobank:task')
const dpack = require('dpack')

task('deploy-ricobank', '')
  .addOptionalParam('mock', 'Ignore dependency args and deploy new mock dependencies')
  .addOptionalParam('dependencies', 'Pack with all required dependencies')
  .setAction(async (args, hre) => {
    debug('network name in task:', hre.network.name)
    const [ali] = await hre.ethers.getSigners()

    if (args.mock && args.dependencies) {
      throw new Error('Panic: don\'t use \'mock\' and \'dependencies\' together')
    }
    let deps
    if (args.dependencies) {
      deps = args.dependencies
    } else if (args.mock) {
      deps = await hre.run('deploy-mock-dependencies')
    } else {
      throw new Error('Panic: must provide either \'mock\' or \'dependencies\'')
    }

    const pb = new dpack.PackBuilder(hre.network.name)

    const contracts = [['RicoFlowerV1', require('../artifacts/sol/flow.sol/RicoFlowerV1.json')],
                       ['Join', require('../artifacts/sol/join.sol/Join.json')],
                       ['Plotter', require('../artifacts/sol/plot.sol/Plotter.json')],
                       ['Port', require('../artifacts/sol/port.sol/Port.json')],
                       ['Vat', require('../artifacts/sol/vat.sol/Vat.json')],
                       ['Vow', require('../artifacts/sol/vow.sol/Vow.json')],
                       ['Vox', require('../artifacts/sol/vox.sol/Vox.json')]]

    for await (const [typename, artifact] of contracts) {
      const deployer = hre.ethers.ContractFactory.fromSolidity(artifact, ali)
      const contract = await deployer.deploy()
      await pb.packObject({
        objectname: typename.toLowerCase(),
        address: contract.address,
        typename: typename,
        artifact: artifact
      })
    }

    const gem_artifact = await dpack.getIpfsJson(deps.types.Gem.artifact['/'])
    const deps_dapp = await dpack.Dapp.loadFromPack(deps, ali, hre.ethers)
    for (const [name, symbol] of [['Rico', 'RICO'], ['Rico Riskshare', 'RISK']]) {
      const receipt = await send(deps_dapp.objects.gemfab.build, name, symbol)
      const [, address] = receipt.events.find(event => event.event === 'Build').args
      await pb.packObject({
        objectname: symbol.toLowerCase(),
        address: address,
        typename: 'Gem',
        artifact: gem_artifact
      }, false)
    }

    await pb.merge(deps)
    return await pb.build()
  })
