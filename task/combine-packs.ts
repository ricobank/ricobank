import { task } from 'hardhat/config'
const dpack = require('@etherpacks/dpack')

task('combine-packs', 'merge a set of pack cids and print result pack cid')
    .addVariadicPositionalParam('ipfsHashes', 'An array of IPFS hashes to process', [])
    .setAction(async ({ipfsHashes}, hre) => {
        const packs = [];
        for (const hash of ipfsHashes) {
            const pack = await dpack.getIpfsJson(hash);
            packs.push(pack);
        }
        const pb = new dpack.PackBuilder(hre.network.name)
        await pb.merge(...packs)
        const pack = await pb.build();
        console.log(await dpack.putIpfsJson(pack))
});
