const { ethers } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log('Deploying contracts with the account: ' + deployer.address);

    const ONE_DAY = "86400";
    const SEVEN_DAY = "604800";

    const ERC20Factory = await ethers.getContractFactory('MockERC20');

    const rewardToken = "0x3aACa0C638cDc7384017CD811Db519e605599D51";
    const pdt = "0xac532B0DEB77c65F95A609d53f8726aD6c4Edc78";

    const Staking = await ethers.getContractFactory('PDTStaking');
    const staking = await Staking.deploy(SEVEN_DAY, ONE_DAY, pdt, rewardToken, deployer.address);

    console.log("Reward Token: " + rewardToken);
    console.log("PDT: " + pdt);
    console.log("Staking: " + staking.address);
}

main()
    .then(() => process.exit())
    .catch(error => {
        console.error(error);
        process.exit(1);
})