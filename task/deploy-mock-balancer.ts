import {task} from 'hardhat/config'
import {HardhatRuntimeEnvironment, TaskArguments} from 'hardhat/types'

const balancer = require('@balancer-labs/v2-deployments')

task('deploy-mock-balancer', 'deploys balancer vault')
    .setAction(async (args: TaskArguments, hre: HardhatRuntimeEnvironment) => {
        const {ethers, network} = hre
        const [acct] = await hre.ethers.getSigners()
        const deployer = acct.address
        const WETH = args.WETH

        const vault_abi = await balancer.getBalancerContractAbi('20210418-vault', 'Vault')
        const vault_code = await balancer.getBalancerContractBytecode('20210418-vault', 'Vault')
        const poolfab_abi = await balancer.getBalancerContractAbi('20210418-weighted-pool', 'WeightedPoolFactory')
        const poolfab_code = await balancer.getBalancerContractBytecode('20210418-weighted-pool', 'WeightedPoolFactory')

        const vault_type = new ethers.ContractFactory(vault_abi, vault_code, acct)
        const poolfab_type = new ethers.ContractFactory(poolfab_abi, poolfab_code, acct)

        const vault = await vault_type.deploy(deployer, WETH.address, 1000, 1000)
        const poolfab = await poolfab_type.deploy(vault.address)

        return {vault: vault, poolfab: poolfab}

        // let vault_artifact = {
        //     contractName: 'Vault',
        //     abi: vault_abi,
        //     bytecode: vault_code
        // }
        // const vault_artifact_cid = (await dpack.putIpfsJson(vault_artifact)).toString()
        //
        // let poolfab_artifact = {
        //     contractName: 'WeightedPoolFactory',
        //     abi: poolfab_abi,
        //     bytecode: poolfab_code
        // }
        // const poolfab_artifact_cid = (await dpack.putIpfsJson(poolfab_artifact)).toString()
        //
        // const out = {
        //     format: 'dpack-1',
        //     network: network.name,
        //     types: {},
        //     objects: {}
        // }
        // out.types['Vault'] = {
        //     typename: 'Vault',
        //     artifacts: {"/": vault_artifact_cid},
        // }
        // out.types['WeightedPoolFactory'] = {
        //     typename: 'WeightedPoolFactory',
        //     artifacts: {"/": poolfab_artifact_cid},
        // }
        // out.objects['vault'] = {
        //     name: 'vault',
        //     typename: 'Vault',
        //     artifacts: {"/": vault_artifact_cid},
        //     address: vault.address
        // }
        // out.objects['poolfab'] = {
        //     name: 'poolfab',
        //     typename: 'WeightedPoolFactory',
        //     artifacts: {"/": poolfab_artifact_cid},
        //     address: poolfab.address
        // }
        // const json = JSON.stringify(out, null, 2)
    })
