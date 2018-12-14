const House = artifacts.require('House.sol')
const EconomicalModel = {
  Quota: 0,
  Charge: 1
}
const executor = "0x46a23e25df9a0f6c18729dda9ad1af3b6a131160"
module.exports = deployer => {
  deployer.deploy(House, EconomicalModel.Quota, executor)
}
