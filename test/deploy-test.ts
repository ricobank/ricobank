import { want } from 'minihat'
const hh = require('hardhat')

describe('deploy-ricobank task', ()=>{
  it('deploy', async() => {
    const pack = await hh.run('deploy-ricobank', {mock:'true'});
    want(pack.objects.vat).exists
  })
})
