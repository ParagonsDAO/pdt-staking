import axios from "axios";
import * as dotenv from "dotenv";
const { ethers } = require("hardhat");
const { Flipside } = require("@flipsidecrypto/sdk");

dotenv.config();

const CONTRACT_ADDRESS = "0xE09c8a88982A85C5B76b1756ec6172d4ad2549D6";
const CONTRACT_DEPLOYMENT_BLOCK = 15637871;
const StakingABI = require("../abis/pdtStaking.json");
const FUNDING: { [i: number]: number } = {
    1: 52173,
    2: 52173,
    3: 34782,
    4: 34782,
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

const getUserWeightAtEpoch = async (address: string, epochId: number) => {
    const [signer] = await ethers.getSigners();
    const contract = new ethers.Contract(CONTRACT_ADDRESS, StakingABI, signer);
    // Parameters for your function call go here.
    const functionParams: any[] = [address, epochId];
    const functionName = "userWeightAtEpoch";
    const input = contract.interface.encodeFunctionData(functionName, functionParams);

    // assuming environment variables TENDERLY_USER, TENDERLY_PROJECT and TENDERLY_ACCESS_KEY are set
    // https://docs.tenderly.co/other/platform-access/how-to-find-the-project-slug-username-and-organization-name
    // https://docs.tenderly.co/other/platform-access/how-to-generate-api-access-tokens
    const { TENDERLY_USER, TENDERLY_PROJECT, TENDERLY_ACCESS_KEY } = process.env;

    const resp = await axios.post(
        `https://api.tenderly.co/api/v1/account/${TENDERLY_USER}/project/${TENDERLY_PROJECT}/simulate`,
        // the transaction
        {
            /* Simulation Configuration */
            save: false, // if true simulation is saved and shows up in the dashboard
            save_if_fails: false, // if true, reverting simulations show up in the dashboard
            simulation_type: "full", // full or quick (full is default)
            network_id: "1", // network to simulate on
            // simulate transaction at this (historical) block number
            // block_number: 16527769,
            // simulate transaction at this index within the (historical) block
            // transaction_index: 42,
            /* Standard EVM Transaction object */
            from: "0xdc6bdc37b2714ee601734cf55a05625c9e512461",
            to: CONTRACT_ADDRESS,
            input,
            gas: 8000000,
            gas_price: 0,
            value: 0,
        },
        {
            headers: {
                "X-Access-Key": TENDERLY_ACCESS_KEY as string,
            },
        }
    );

    const transaction = resp.data.transaction;
    const callTrace = transaction.transaction_info.call_trace;
    return callTrace.decoded_output[0].value;
};

const getContractWeightAtEpoch = async (epochId: number) => {
    const [signer] = await ethers.getSigners();
    const contract = new ethers.Contract(CONTRACT_ADDRESS, StakingABI, signer);
    // Parameters for your function call go here.
    const functionParams: any[] = [epochId];
    const functionName = "contractWeightAtEpoch";
    const input = contract.interface.encodeFunctionData(functionName, functionParams);

    // assuming environment variables TENDERLY_USER, TENDERLY_PROJECT and TENDERLY_ACCESS_KEY are set
    // https://docs.tenderly.co/other/platform-access/how-to-find-the-project-slug-username-and-organization-name
    // https://docs.tenderly.co/other/platform-access/how-to-generate-api-access-tokens
    const { TENDERLY_USER, TENDERLY_PROJECT, TENDERLY_ACCESS_KEY } = process.env;

    const resp = await axios.post(
        `https://api.tenderly.co/api/v1/account/${TENDERLY_USER}/project/${TENDERLY_PROJECT}/simulate`,
        // the transaction
        {
            /* Simulation Configuration */
            save: false, // if true simulation is saved and shows up in the dashboard
            save_if_fails: false, // if true, reverting simulations show up in the dashboard
            simulation_type: "full", // full or quick (full is default)
            network_id: "1", // network to simulate on
            // simulate transaction at this (historical) block number
            // block_number: 16527769,
            // simulate transaction at this index within the (historical) block
            // transaction_index: 42,
            /* Standard EVM Transaction object */
            from: "0xdc6bdc37b2714ee601734cf55a05625c9e512461",
            to: CONTRACT_ADDRESS,
            input,
            gas: 8000000,
            gas_price: 0,
            value: 0,
        },
        {
            headers: {
                "X-Access-Key": TENDERLY_ACCESS_KEY as string,
            },
        }
    );

    const transaction = resp.data.transaction;
    const callTrace = transaction.transaction_info.call_trace;
    return callTrace.decoded_output[0].value;
};

async function main() {
    // const allUsers = await getAllUsers();
    const allUsers = ["0xE90b420A71e16376260f9e733da6311D9430a7Ec"];
    const epochsToCheck = [1, 2, 3, 4];
    console.log(`Found ${allUsers.length} users`);

    for (const epochId of epochsToCheck) {
        console.log(`Epoch ${epochId}`);
        for (const user of allUsers) {
            const weight = await getUserWeightAtEpoch(user, epochId);
            const contractWeight = await getContractWeightAtEpoch(epochId);
            console.log(
                `User ${user} has weight ${weight} and contract has weight ${contractWeight}`
            );

            const FUNDS = (FUNDING[epochId] * weight) / contractWeight;
            console.log(FUNDS);
        }
    }
}

main()
    .then(() => process.exit())
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
