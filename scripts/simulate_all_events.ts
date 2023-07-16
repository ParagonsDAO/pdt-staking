import { PrismaClient } from "@prisma/client";
import dotenv from "dotenv";
const { ethers } = require("hardhat");
dotenv.config();

const prisma = new PrismaClient();
const ONE_DAY = "86400";
const SEVEN_DAY = "604800";

async function main() {
    const [deployer, user, user2] = await ethers.getSigners();
    const txns = await prisma.transaction.findMany({});

    const ERC20Factory = await ethers.getContractFactory("MockERC20");
    const StakingFactory = await ethers.getContractFactory("PDTStaking");

    const pdt = await ERC20Factory.deploy("Test PDT", "TPDT");
    const prime = await ERC20Factory.deploy("Test Prime", "TPRIME");
    const staking = await StakingFactory.deploy(
        SEVEN_DAY,
        ONE_DAY,
        ONE_DAY,
        pdt.address,
        prime.address,
        deployer.address
    );
}

main()
    .then(() => process.exit())
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
