const uniV2Staking = artifacts.require("uniV2Staking");

module.exports = function (deployer) {
  deployer.deploy(uniV2Staking);
};
