import "dotenv/config";
import { createPublicClient, createWalletClient, http } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { bsc, bscTestnet } from "viem/chains";
import fs from "fs";
import { isAddress } from "viem";
import RockyCatV2Artifact from "../artifacts/contracts/RockyCatV2.sol/RockyCatV2.json";

// ===== CONFIG =====
const NETWORK = process.argv[2] || "local";
const BATCH_SIZE = 500;
let rpcUrl: string;
let chain;

switch (NETWORK) {
  case "testnet":
    rpcUrl = process.env.BSC_TESTNET_RPC_URL!;
    chain = bscTestnet;
    break;
  case "mainnet":
    rpcUrl = process.env.BSC_MAINNET_RPC_URL!;
    chain = bsc;
    break;
  case "local":
  default:
    rpcUrl = process.env.LOCAL_RPC_URL!;
    chain = undefined;
}

// ===== SETUP CLIENTS =====
const PRIVATE_KEY = process.env.PRIVATE_KEY as `0x${string}`;
if (!PRIVATE_KEY) throw new Error("Missing PRIVATE_KEY in .env");
const account = privateKeyToAccount(PRIVATE_KEY);

const walletClient = createWalletClient({
  account,
  chain,
  transport: http(rpcUrl),
});

const publicClient = createPublicClient({
  chain,
  transport: http(rpcUrl),
});
0x8464135c8f25da09e49bc8782676a84730c318bc

// ===== CONFIGURE AIRDROP =====
const CONTRACT_ADDRESS = "0x6eb1e5d89130a97a6f644463f0045d2da6105da3";
const airdropData = JSON.parse(fs.readFileSync("airdrop.json", "utf-8"));
const recipients = airdropData.recipients;
const amounts = airdropData.amounts.map((amount: string) => BigInt(amount));

// Validate data
if (recipients.length !== amounts.length) throw new Error("Recipients and amounts length mismatch");
if (recipients.length === 0) throw new Error("Empty airdrop list");
recipients.forEach((addr: string, i: number) => {
  if (!isAddress(addr)) throw new Error(`Invalid address at index ${i}: ${addr}`);
});

async function main() {
  console.log(`🚀 Running airdropMint on network: ${NETWORK}`);
  console.log("Using account:", account.address);
  console.log("Total recipients:", recipients.length);

  // Check balance
  const balance = await publicClient.getBalance({ address: account.address });
  console.log("BNB Balance:", Number(balance) / 1e18);

  // Split into batches
  const batches = [];
  for (let i = 0; i < recipients.length; i += BATCH_SIZE) {
    batches.push({
      recipients: recipients.slice(i, i + BATCH_SIZE),
      amounts: amounts.slice(i, i + BATCH_SIZE),
    });
  }
  console.log(`Split into ${batches.length} batches of ${BATCH_SIZE} recipients each`);

  // Process batches sequentially
  for (let i = 0; i < batches.length; i++) {
    const batch = batches[i];
    console.log(`Processing batch ${i + 1}/${batches.length} (${batch.recipients.length} recipients)`);

    // Estimate gas
    // const gasEstimate = await publicClient.estimateContractGas({
    //   account,
    //   address: CONTRACT_ADDRESS,
    //   abi: RockyCatV2Artifact.abi,
    //   functionName: "airdropMint",
    //   args: [batch.recipients, batch.amounts],
    // });
    // console.log(`Batch ${i + 1} Estimated Gas:`, gasEstimate);

    // Execute airdrop
    const txHash = await walletClient.writeContract({
      account,
      address: CONTRACT_ADDRESS,
      abi: RockyCatV2Artifact.abi,
      functionName: "airdropMint",
      args: [batch.recipients, batch.amounts]
    });

    console.log(`Batch ${i + 1} Transaction sent:`, txHash);

    // Wait for confirmation
    const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
    console.log(`Batch ${i + 1} Transaction confirmed:`, receipt.transactionHash);
  }

  console.log("✅ Airdrop complete for all batches!");
}

main().catch((err) => {
  console.error("❌ Airdrop failed:", err);
  process.exit(1);
});