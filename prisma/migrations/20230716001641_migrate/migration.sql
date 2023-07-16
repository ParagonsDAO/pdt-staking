/*
  Warnings:

  - The primary key for the `Transaction` table will be changed. If it partially fails, the table could be left without primary key constraint.
  - You are about to drop the column `id` on the `Transaction` table. All the data in the column will be lost.

*/
-- AlterTable
ALTER TABLE "Transaction" DROP CONSTRAINT "Transaction_pkey",
DROP COLUMN "id",
ALTER COLUMN "max_fee_per_gas" DROP NOT NULL,
ADD CONSTRAINT "Transaction_pkey" PRIMARY KEY ("tx_hash");
