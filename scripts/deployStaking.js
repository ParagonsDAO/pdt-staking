const { ethers } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account: " + deployer.address);

    const ONE_DAY = "86400";
    const SEVEN_DAY = "604800";

    const ERC20 = await ethers.getContractFactory("MockERC20");

    const pdt = await ERC20.deploy("TEST PDT", "TPDT");
    const prime = await ERC20.deploy("TEST PRIME", "TPRM");

    const Staking = await ethers.getContractFactory("PDTStaking");
    const staking = await Staking.deploy(
        SEVEN_DAY,
        ONE_DAY,
        ONE_DAY,
        pdt.address,
        prime.address,
        deployer.address
    );

    console.log("Prime: " + prime.address);
    console.log("PDT: " + pdt.address);
    console.log("Staking: " + staking.address);
}

main()
    .then(() => process.exit())
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
