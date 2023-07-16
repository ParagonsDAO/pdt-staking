const { Flipside } = require("@flipsidecrypto/sdk");
import { PrismaClient } from "@prisma/client";
import dotenv from "dotenv";
dotenv.config();

const prisma = new PrismaClient();

// Contract creation txHASH = 0x47ee9f95120b197b19246fcdee95de69d5b276681095ff06cf3e1c91c009f886

const CONTRACT_ADDRESS = "0xE09c8a88982A85C5B76b1756ec6172d4ad2549D6";
const CONTRACT_DEPLOYMENT_BLOCK = 15637871;

async function getStakingTxnsFromFlipside() {
    const flipside = new Flipside(
        process.env.FLIPSIDE_API_KEY,
        "https://api-v2.flipsidecrypto.xyz"
    );
    const sql = `SELECT * FROM ethereum.core.fact_transactions WHERE TO_ADDRESS = lower('${CONTRACT_ADDRESS}') AND BLOCK_NUMBER >= ${CONTRACT_DEPLOYMENT_BLOCK}`;
    const res = await flipside.query.run({ sql: sql });
    return res;
}

async function main() {
    const { records, page } = await getStakingTxnsFromFlipside();
    console.log(`Page stats: ${JSON.stringify(page)}`);

    await prisma.transaction.createMany({
        data: records.map((i: any) => {
            delete i.__row_index;
            return i;
        }),
        skipDuplicates: true,
    });

    console.log(`Inserted ${records.length} records`);
}

main()
    .then(() => process.exit())
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
