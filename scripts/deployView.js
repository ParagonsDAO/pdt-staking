const { ethers } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log('Deploying contracts with the account: ' + deployer.address);

    const pdtStaking = "0x0cA28299f7bc2D4f821Cb651EC5e193C663AEf2c";

    const StakingView = await ethers.getContractFactory('PDTStakingView');
    const stakingView = await StakingView.deploy(pdtStaking);

    console.log("Staking View: " + stakingView.address);
}

main()
    .then(() => process.exit())
    .catch(error => {
        console.error(error);
        process.exit(1);
})