import axios from "axios";
import * as dotenv from "dotenv";
const { ethers } = require("hardhat");
const { Flipside } = require("@flipsidecrypto/sdk");
import type EthersT from "ethers";
// const fs = require("fs");÷
import fs from "fs";

dotenv.config();

// Replace with your actual Infura RPC URL
const infuraProvider = new ethers.providers.JsonRpcProvider(process.env.INFURA_RPC_ENDPOINT);

const CONTRACT_ADDRESS = "0xE09c8a88982A85C5B76b1756ec6172d4ad2549D6";
const CONTRACT_DEPLOYMENT_BLOCK = 15637871;
const StakingABI = require("../abis/pdtStaking.json");
const FUNDING: { [i: number]: EthersT.BigNumber } = {
    1: ethers.utils.parseUnits("52173"),
    2: ethers.utils.parseUnits("52173"),
    3: ethers.utils.parseUnits("34782"),
    4: ethers.utils.parseUnits("34782"),
};

const getAllUsers = async () => {
    const flipside = new Flipside(
        process.env.FLIPSIDE_API_KEY,
        "https://api-v2.flipsidecrypto.xyz"
    );
    const sql = `SELECT
      DISTINCT(FROM_ADDRESS)
    FROM
      ethereum.core.fact_transactions
    WHERE
      TO_ADDRESS = lower('${CONTRACT_ADDRESS}')
      AND BLOCK_NUMBER >= ${CONTRACT_DEPLOYMENT_BLOCK}
    `;
    const res = await flipside.query.run({ sql: sql });
    return res.rows.map((i: any) => i[0]);
};
async function getUserWeightAtEpoch(
    address: string,
    epochId: number,
    retries = 5
): Promise<EthersT.BigNumber> {
    const maxRetries = retries;
    let attempt = 0;
    while (attempt < maxRetries) {
        try {
            const contract = new ethers.Contract(CONTRACT_ADDRESS, StakingABI, infuraProvider);
            const functionParams: any[] = [address, epochId];
            const functionName = "userWeightAtEpoch";
            const userWeight = await contract[functionName](...functionParams);
            return userWeight;
        } catch (error: any) {
            console.log(
                `Error in getUserWeightAtEpoch: ${error.message}, retrying... (${
                    attempt + 1
                }/${maxRetries})`
            );
            attempt++;
        }
    }
    throw new Error(`Failed to get user weight at epoch after ${maxRetries} retries.`);
}
const getContractWeightAtEpoch = async (epochId: number): Promise<EthersT.BigNumber> => {
    const contract = new ethers.Contract(CONTRACT_ADDRESS, StakingABI, infuraProvider);
    // Parameters for your function call go here.
    const functionParams: any[] = [epochId];
    const functionName = "contractWeightAtEpoch";
    const contractWeight = await contract[functionName](...functionParams);

    return contractWeight;
};

async function main() {
    const allUsers = await getAllUsers();
    // const allUsers = ["0xE90b420A71e16376260f9e733da6311D9430a7Ec"];
    const epochsToCheck = [1, 2, 3, 4];

    const contractOwes: { [i: string]: EthersT.BigNumber } = {};
    console.log(`Found ${allUsers.length} users`);

    for (const epochId of epochsToCheck) {
        console.log(`Epoch ${epochId}`);
        const contractWeight = await getContractWeightAtEpoch(epochId);
        const promises = allUsers.map(async (user: string) => {
            const weight = await getUserWeightAtEpoch(user, epochId);
            console.log(
                `User ${user} has weight ${weight} and contract has weight ${contractWeight}`
            );
            const fundsOweThisEpoch = FUNDING[epochId].mul(weight).div(contractWeight);

            if (!contractOwes[user]) contractOwes[user] = ethers.BigNumber.from(0);
            contractOwes[user] = contractOwes[user].add(fundsOweThisEpoch);
        });

        await Promise.all(promises);
    }

    const csv: string[] = [];
    for (const user of Object.keys(contractOwes)) {
        const contractOwesInEther = ethers.utils.formatEther(contractOwes[user]);
        csv.push(`${user},${contractOwesInEther}`);
    }
    console.log(csv.join("\n"));
    fs.writeFileSync("scripts/contract_owes2.csv", csv.join("\n"));
}

main()
    .then(() => process.exit())
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
