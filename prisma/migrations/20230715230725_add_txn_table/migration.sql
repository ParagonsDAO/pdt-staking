/*
  Warnings:

  - You are about to drop the `User` table. If the table is not empty, all the data it contains will be lost.

*/
-- DropTable
DROP TABLE "User";

-- CreateTable
CREATE TABLE "Transaction" (
    "id" SERIAL NOT NULL,
    "block_number" INTEGER NOT NULL,
    "block_timestamp" TIMESTAMP(3) NOT NULL,
    "block_hash" TEXT NOT NULL,
    "tx_hash" TEXT NOT NULL,
    "nonce" INTEGER NOT NULL,
    "position" INTEGER NOT NULL,
    "origin_function_signature" TEXT NOT NULL,
    "from_address" TEXT NOT NULL,
    "to_address" TEXT NOT NULL,
    "eth_value" DOUBLE PRECISION NOT NULL,
    "tx_fee" DOUBLE PRECISION NOT NULL,
    "gas_price" DOUBLE PRECISION NOT NULL,
    "gas_limit" INTEGER NOT NULL,
    "gas_used" INTEGER NOT NULL,
    "cumulative_gas_used" INTEGER NOT NULL,
    "input_data" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "effective_gas_price" DOUBLE PRECISION NOT NULL,
    "max_fee_per_gas" DOUBLE PRECISION NOT NULL,
    "max_priority_fee_per_gas" DOUBLE PRECISION NOT NULL,
    "r" TEXT NOT NULL,
    "s" TEXT NOT NULL,
    "v" TEXT NOT NULL,
    "tx_type" INTEGER NOT NULL,
    "chain_id" INTEGER NOT NULL,

    CONSTRAINT "Transaction_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Transaction_tx_hash_key" ON "Transaction"("tx_hash");
