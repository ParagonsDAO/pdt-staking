const { ethers } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log('Deploying contracts with the account: ' + deployer.address);

    const ONE_DAY = "86400";
    const SEVEN_DAY = "604800";

    const ERC20Factory = await ethers.getContractFactory('MockERC20');

    const rewardToken = await ERC20Factory.deploy();
    const pdt = await ERC20Factory.deploy();

    const Staking = await ethers.getContractFactory('PDTStaking');
    const staking = await Staking.deploy(SEVEN_DAY, ONE_DAY, pdt.address, rewardToken.address);

    console.log("Reward Token: " + rewardToken.address);
    console.log("PDT: " + pdt.address);
    console.log("Staking: " + staking.address);
}

main()
    .then(() => process.exit())
    .catch(error => {
        console.error(error);
        process.exit(1);
})