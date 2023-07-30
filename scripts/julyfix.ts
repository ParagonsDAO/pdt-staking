import assert from "assert";
import axios from "axios";
import * as dotenv from "dotenv";
const { ethers } = require("hardhat");
const { Flipside } = require("@flipsidecrypto/sdk");
import type EthersT from "ethers";
import fs from "fs";

dotenv.config();

// Replace with your actual Infura RPC URL
const infuraProvider = new ethers.providers.JsonRpcProvider(process.env.INFURA_RPC_ENDPOINT);

const CONTRACT_ADDRESS = "0xE09c8a88982A85C5B76b1756ec6172d4ad2549D6";
const StakingABI = require("../abis/pdtStaking.json");
const FUNDING: { [i: number]: EthersT.BigNumber } = {
    1: ethers.utils.parseUnits("52173"),
    2: ethers.utils.parseUnits("52173"),
    3: ethers.utils.parseUnits("34782"),
    4: ethers.utils.parseUnits("34782"),
    5: ethers.utils.parseUnits("26087"),
};

const getAllUsers = async (): Promise<string[]> => {
    const users: Set<string> = new Set();
    const provider = new ethers.providers.JsonRpcProvider(process.env.INFURA_RPC_ENDPOINT);

    // ABI of the Staked event
    const stakedABI = [
        "event Staked(address to, uint256 indexed newStakeAmount, uint256 indexed newWeightAmount)",
    ];
    // Create a contract instance
    const contract = new ethers.Contract(CONTRACT_ADDRESS, stakedABI, provider);
    // Define the filter for the Staked event
    const filter = contract.filters.Staked(null, null, null);
    // Get past events
    const logs = await provider.getLogs({
        fromBlock: 0, // Replace with the block from which you want to start looking for events
        toBlock: "latest",
        address: CONTRACT_ADDRESS,
        topics: filter.topics,
    });

    // Parse the logs
    for (let log of logs) {
        const event = contract.interface.parseLog(log);
        users.add(event.args.to as string);
    }
    return Array.from(users);
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
    let allUsers = await getAllUsers();
    console.log(`Found ${allUsers.length} users`);
    // const allUsers = ["0xE90b420A71e16376260f9e733da6311D9430a7Ec"];
    const epochsToCheck = [5];

    const contractOwes: { [i: string]: EthersT.BigNumber } = {};

    for (const epochId of epochsToCheck) {
        console.log(`Epoch ${epochId}`);
        const contractWeight = await getContractWeightAtEpoch(epochId);
        let totalUserWeight = ethers.BigNumber.from(0);
        const promises = allUsers.map(async (user: string) => {
            const userWeight = await getUserWeightAtEpoch(user, epochId);
            console.log(
                `User ${user} has weight ${userWeight} and contract has weight ${contractWeight}`
            );
            const fundsOweThisEpoch = FUNDING[epochId].mul(userWeight).div(contractWeight);

            totalUserWeight = totalUserWeight.add(userWeight);
            if (!contractOwes[user]) contractOwes[user] = ethers.BigNumber.from(0);
            contractOwes[user] = contractOwes[user].add(fundsOweThisEpoch);
        });

        await Promise.all(promises);

        console.log({ totalUserWeight, contractWeight });

        {
            const contract = new ethers.Contract(CONTRACT_ADDRESS, StakingABI, infuraProvider);
            // Parameters for your function call go here.
            const functionName = "totalStaked";
            const totalStaked = await contract[functionName]();

            let totalUserStaked = ethers.BigNumber.from(0);
            const promises = allUsers.map(async (user: string) => {
                const stakeDetails = await contract["stakeDetails"](user);
                totalUserStaked = totalUserStaked.add(stakeDetails.amountStaked);
            });

            await Promise.all(promises);
            console.log({ totalUserStaked, totalStaked });
        }
    }

    const csv: string[] = [];
    for (const user of Object.keys(contractOwes)) {
        csv.push(`${user},${contractOwes[user]}`);
    }

    fs.writeFileSync("scripts/contract_owes_epoch_5.csv", csv.join("\n"));

    // check sum
    const sum = Object.values(contractOwes).reduce((a, b) => a.add(b), ethers.BigNumber.from(0));
    console.log(`${ethers.utils.formatEther(sum)} PRIME to payout`);
}

main()
    .then(() => process.exit())
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
