import axios from "axios";
import * as dotenv from "dotenv";
const { ethers } = require("hardhat");
dotenv.config();

const CONTRACT_ADDRESS = "0xE09c8a88982A85C5B76b1756ec6172d4ad2549D6";
const StakingABI = require("../abis/pdtStaking.json");
const staingInterface = new ethers.utils.Interface(StakingABI);

const getWeight = async () => {
    const [signer] = await ethers.getSigners();
    const contract = new ethers.Contract(CONTRACT_ADDRESS, StakingABI, signer);
    // Parameters for your function call go here.
    const functionParams: any[] = ["0xE90b420A71e16376260f9e733da6311D9430a7Ec", 1];
    const functionName = "userWeightAtEpoch";
    const input = contract.interface.encodeFunctionData(functionName, functionParams);

    // assuming environment variables TENDERLY_USER, TENDERLY_PROJECT and TENDERLY_ACCESS_KEY are set
    // https://docs.tenderly.co/other/platform-access/how-to-find-the-project-slug-username-and-organization-name
    // https://docs.tenderly.co/other/platform-access/how-to-generate-api-access-tokens
    const { TENDERLY_USER, TENDERLY_PROJECT, TENDERLY_ACCESS_KEY } = process.env;

    console.time("Simulation");

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
    console.timeEnd("Simulation");

    const transaction = resp.data.transaction;
    // access the transaction call trace
    const callTrace = transaction.transaction_info.call_trace;
    console.log(JSON.stringify(callTrace.decoded_output, null, 2));
};

getWeight();
