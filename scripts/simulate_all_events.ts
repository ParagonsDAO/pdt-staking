import { PrismaClient, Transaction } from "@prisma/client";
import dotenv from "dotenv";
import type EthersT from "ethers";
const { ethers } = require("hardhat");
dotenv.config();

const prisma = new PrismaClient();
const ONE_DAY = "86400";
const SEVEN_DAY = "604800";

const getFakeSigners = (txns: Transaction[]) => {
    const allUsers = new Set(txns.map((txn) => txn.from_address));

    const bindings: { originalAddress: string; simulatedWallet: EthersT.Signer }[] = [];
    for (const i of Array.from(allUsers)) {
        bindings.push({
            originalAddress: i,
            simulatedWallet: ethers.Wallet.createRandom(),
        });
    }

    return bindings;
};

async function main() {
    const txns = await prisma.transaction.findMany({});
    const bindings = getFakeSigners(txns);

    const [deployer] = await ethers.getSigners();

    const ERC20Factory = await ethers.getContractFactory("MockERC20");
    const StakingFactory = await ethers.getContractFactory("PDTStaking");

    const pdt = await ERC20Factory.deploy("Test PDT", "TPDT");
    const prime = await ERC20Factory.deploy("Test Prime", "TPRIME");
    // ASSUME THESE ARE THE CONSTRUCTOR ARGS
    const staking = await StakingFactory.deploy(
        SEVEN_DAY,
        ONE_DAY,
        ONE_DAY,
        pdt.address,
        prime.address,
        deployer.address
    );

    console.log(txns, bindings);
}

main()
    .then(() => process.exit())
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
